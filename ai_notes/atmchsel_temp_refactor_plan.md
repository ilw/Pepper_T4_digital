## Goal

Refactor temperature sensing so that:

- `ATMCHSEL` becomes **8-bit** (one-hot for the 8 analogue channels only).
- The **temperature input selection** on the analogue mux is controlled by `ENMONTSENSE_sync` (rather than `ATMCHSEL[9:8]`).
- Only one of `ENSAMP_sync` or `ENMONTSENSE_sync` is asserted at any time (mutually exclusive modes).
- Temperature sensing is handled by a **separate dedicated block**, not mixed into `ATM_Control`.
- Temperature capture becomes a **one-shot** (single conversion per request) without requiring the analogue side to write any registers.


## Current design (as implemented today)

- `ATMCHSEL` is **10 bits** in `ATM_Control` and top-level `TLM`.
  - Bits `[7:0]` are used as a one-hot channel select for normal sampling.
  - Bits `[9:8]` are used in “temperature mode” to alternate between two temperature inputs.
- `ATM_Control` currently asserts:
  - `nARST = ENSAMP_sync | ENMONTSENSE_sync`
  - and sequences:
    - sampling channel cycling when `ENSAMP_sync=1`
    - temperature toggling when `ENMONTSENSE_sync=1`
- `Dual_phase_gated_burst_divider` already gates `SAMPLE_CLK` with:
  - `enable = ENSAMP_sync | ENMONTSENSE_sync`
  - so temperature mode can already receive `SAMPLE_CLK` (good — the “divider off when ENSAMP low” concern is already addressed).
- `Temperature_Buffer` latches *two* temperatures based on `ATMCHSEL[9]` and `ATMCHSEL[8]`.


## Proposed architecture

### 1) Make “mode” explicit (sampling vs temp-sense)

Define two internal mode enables (already effectively true today):

- **Sampling mode**: `mode_samp = ENSAMP_sync`
- **Temp-sense mode**: `mode_temp = ENMONTSENSE_sync`

Assumption (as per your note): `mode_samp` and `mode_temp` are mutually exclusive.


### 2) Reduce `ATMCHSEL` to 8 bits everywhere

Change the width in:

- `TLM` top-level port `ATMCHSEL` → `output wire [7:0] ATMCHSEL`
- `ATM_Control` output `ATMCHSEL` → `output wire [7:0] ATMCHSEL`
- Any internal wires in `TLM` (e.g. `atm_control_atmchsel`) to `[7:0]`
- `FIFO` input `ATMCHSEL` → `input wire [7:0] ATMCHSEL`
  - (FIFO already only uses `[7:0]` today, so this becomes a type cleanup rather than a functional change.)

Remove all logic that depends on `ATMCHSEL[9:8]`.


### 3) Stop using `ATM_Control` for temperature selection

Update `ATM_Control` so it only handles sampling sequencing:

- Inputs: keep `SAMPLE_CLK`, `ENSAMP_sync`, `CHEN_sync`, `DONE`, `NRST_sync`, `ENLOWPWR_sync`
- Remove `ENMONTSENSE_sync` input entirely
- Outputs:
  - Keep `ATMCHSEL[7:0]` (sampling one-hot only)
  - Keep `CHSEL[7:0]` and `LASTWORD`
  - Option A (recommended): keep `nARST` output and define it as `nARST = ENSAMP_sync`
  - Option B: remove `nARST` from `ATM_Control` and generate it at top-level

This makes `ATM_Control` active only when `ENSAMP_sync=1`.


### 4) Add a new temperature sensing controller block

Create a new module, e.g. `TempSense_Control` (name flexible), responsible for:

- Driving the ADC “start/enable” behavior during temp-sense mode
- Capturing a single temperature result (one-shot)
- Providing a clean “done/valid” indication (optional, but helpful)

Suggested interface (minimal and robust):

- **Inputs**
  - `SAMPLE_CLK`
  - `NRST_sync`
  - `ENMONTSENSE_sync` (mode enable / request)
  - `DONE` (ADC done)
  - `RESULT[15:0]` (ADC result)
- **Outputs**
  - `TEMP_VAL[15:0]`
  - `TEMP_VALID` (optional but recommended)
  - `TEMP_BUSY` (optional)
  - `nARST_TEMP` (or a generic `ADC_START_TEMP`) to request conversions while in temp mode

One-shot behavior without register writes:

- Use an **edge-detect / latch** so temp capture runs only once per `ENMONTSENSE_sync` assertion.
- Example behavior:
  - On rising edge of `ENMONTSENSE_sync`: arm a measurement (`busy=1`, `valid=0`)
  - While `busy=1`: keep `nARST_TEMP=1` (start/keep ADC running)
  - When `DONE` goes high: latch `RESULT` into `TEMP_VAL`, set `valid=1`, set `busy=0`
  - Ignore subsequent `DONE` pulses until `ENMONTSENSE_sync` goes low again (re-arm on next rising edge)

This achieves the “oneshot temperature reading” even if the control register stays high for a long time.


### 5) Select temperature input on the mux using `ENMONTSENSE_sync`

Since the analogue mux will use `ENMONTSENSE_sync` as the selection control:

- Expose a top-level output that the analogue mux can consume.
  - If you truly want the synced version: add top-level output like `TEMPSEL` and drive `TEMPSEL = enmontsense_sync`.
  - Alternatively (simpler physically): reuse the existing top-level `ENMONTSENSE` output (raw reg bit), but that would not be the `_sync` signal you specified.

Recommendation: **add `TEMPSEL` = `ENMONTSENSE_sync` as a top-level output** so the analogue mux selection is aligned to the same clock-domain assumptions as the rest of the temp-sense control.


### 6) Drive the ADC start (`nARST`) from top-level with a clean mode mux

Right now `nARST` is effectively “start/enable ADC conversions”.

With two separate controllers, top-level should combine them:

- `nARST = nARST_SAMP | nARST_TEMP`
  - where `nARST_SAMP` comes from `ATM_Control` (or just equals `ENSAMP_sync`)
  - and `nARST_TEMP` comes from `TempSense_Control`

Because `ENSAMP_sync` and `ENMONTSENSE_sync` are mutually exclusive, this is safe and avoids clock muxing.


### 7) Replace / simplify `Temperature_Buffer`

`Temperature_Buffer` currently assumes **two** temperature channels via `ATMCHSEL[9:8]`.

With a single temperature mux input, you have two good options:

- **Option A (recommended)**: delete or bypass `Temperature_Buffer` and let `TempSense_Control` own the capture register `TEMP_VAL`.
- If `Command_Interpreter` expects temperature readback, expose a single `TEMPVAL[15:0]`.
- **Option B**: keep a slimmed module `Temperature_Buffer_OneShot` that just latches `RESULT` on the temp-sense `DONE` and exposes `TEMP_VAL`.

Recommendation: **move capture into the new temp controller** so “mode + capture + oneshot” is in one place.


## Clocking considerations (HF_CLK too fast concern)

Good news: the current divider already enables `SAMPLE_CLK` for temp mode (`enable = ENSAMP_sync | ENMONTSENSE_sync`).

Remaining question: should temperature conversions run at a different clock than sampling?

- **Phase 1 (do now)**: run temp-sense using the existing `SAMPLE_CLK` configuration.
  - This avoids any additional clock muxing and minimizes risk.
- **Phase 2 (optional later)**: add separate temperature timing config bits (using the spare registers you exposed) to slow the temp conversion rate.
  - Best approach: extend the divider to select between “sampling dividers” and “temp dividers” based on `ENMONTSENSE_sync`.
  - This is not a clock mux at the output pin; it’s choosing which set of counters drives the internal divider logic.


## Concrete implementation steps

1. **Plumb `ATMCHSEL` to 8-bit**
   - Update ports and internal wires in `TLM`, `ATM_Control`, `FIFO`, `Temperature_Buffer`, and any testbenches.
2. **Refactor `ATM_Control`**
   - Remove all `ENMONTSENSE_sync` logic and any temp toggling.
   - Keep only the channel sequencing behavior under `ENSAMP_sync`.
3. **Add `TempSense_Control`**
   - Implement one-shot capture, `nARST_TEMP`, and `TEMP_VAL`.
4. **Top-level wiring in `TLM`**
   - `ATMCHSEL` output comes only from `ATM_Control` (8-bit).
   - Add new top-level output `TEMPSEL = enmontsense_sync` (or equivalent) for the analogue mux.
   - Combine ADC start: `nARST = nARST_SAMP | nARST_TEMP`.
5. **Replace `Temperature_Buffer` usage**
   - Either remove it, or convert it to single-temp and connect to `Command_Interpreter` expectations.
6. **Update tests**
   - Update `tb_top_level_integration.v` and any dummy mux models to use:
     - `ATMCHSEL[7:0]` for channel one-hot
     - `TEMPSEL` (or `ENMONTSENSE_sync` exposure) for selecting temperature input
7. **Sanity checks**
   - Ensure `FIFO` never writes temperature conversions (since `ATMCHSEL=0` during temp mode).
   - Ensure `INT` behavior remains correct (still excludes ENSAMP status bit).


## Open decisions (pick defaults for first implementation)

- **Expose sync vs raw temp select**
  - Default: add `TEMPSEL` driven by `enmontsense_sync`.
- **What to do with existing `TEMP_VAL2`**
  - Update to a single output `TEMPVAL` and remove the second value entirely.
- **Temp capture trigger**
  - Default: rising edge of `ENMONTSENSE_sync` arms capture; clear arm when `ENMONTSENSE_sync` goes low.

