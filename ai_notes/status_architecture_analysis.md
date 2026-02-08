# Status Reporting Architecture: Analysis and Recommendations

## Context

- 8-channel neural recording ASIC; 16-bit ADC at ~1 ksps/channel (SAMPLE_CLK ~8 kHz)
- FIFO buffers frames (1 frame = 8 x 16 bits = 128 bits); DATA_RDY wakes MCU
- MCU reads data over SPI at ~10 MHz
- Two main clock domains: **HF_CLK** (and its derivative SAMPLE_CLK) and **SCK** (SPI)
- Future iterations may be safety-critical; data integrity and fault flagging are paramount
- Area is constrained (implant); FIFO size already under pressure
- Low power is critical for the implant and the wider system


## Current Design

### Status_Monitor (SAMPLE_CLK domain)
- Assembles a 14-bit status word: `{ENSAMP, CFGCHNG, ANALOG_RESET, FIFO_UDF, FIFO_OVF, ADC_OVF, SAT[7:0]}`
- Flags are **sticky**: set on the triggering event, cleared when `status_sent_sync` is high AND the source condition has gone away
- `status_sent` is generated in Command_Interpreter (SCK domain), then synchronised back to SAMPLE_CLK as `status_sent_sync`

### Command_Interpreter (SCK domain)
- Sends status as the first 16-bit SPI word of every transaction (piggy-backed on the command response)
- Status is double-FF synchronised from SAMPLE_CLK into SCK before being placed in `tx_buff`
- `status_sent` fires on the first byte of each transaction, fed back to Status_Monitor to clear flags

### INT pin
- `INT = |status_mon_out[12:0]` (all flags except ENSAMP)
- Active whenever any flag is set

### Known issues with the current approach
1. **Staleness**: the status word the MCU reads is from the *previous* transaction (it was loaded into tx_buff before the MCU's command arrived)
2. **Race on clear**: `status_sent_sync` crosses from SCK back to SAMPLE_CLK. A new event can arrive in the same cycle the flag is being cleared, causing a missed event
3. **Multi-bit CDC**: the 14-bit status bus is synchronised with a simple 2-FF, which is not safe for a multi-bit bus that can change on any SAMPLE_CLK edge. In practice, because these are sticky flags that change slowly relative to SCK, the risk is low — but it is not formally correct
4. **INT stays asserted until clear-on-read**: no way for the MCU to acknowledge an interrupt without reading status, which also clears it


---


## Option A: Status-on-first-word with snapshot (current approach, improved)

### Concept
Keep the current piggy-back scheme but **snapshot** the status into a holding register at the *start* of each SPI transaction (falling edge of CS) so the MCU always reads a coherent, current snapshot rather than last transaction's stale value.

### Changes required
- Add a `status_snapshot` register in Command_Interpreter, latched on CS falling edge (or first SCK after CS falls)
- `tx_buff` in IDLE state serves `status_snapshot` instead of `status_sync[1]`
- `status_sent` still fires, feeding back to clear flags

### Pros
- Minimal area change
- Status is current to within a few SCK cycles of CS assertion
- Compatible with the existing SPI protocol (no firmware change)

### Cons
- Status is still stale by the 2-FF synchroniser latency (2 SCK cycles, ~200 ns at 10 MHz) — acceptable given SAMPLE_CLK is 8 kHz (125 us period)
- Clear-on-read semantics: if the MCU doesn't process the status, it's gone
- Multi-bit CDC concern remains (mitigated by sticky flags + slow change rate)

### CDC safety improvement
Synchronise each flag bit individually (they are independent single-bit sticky flags), not the assembled 14-bit word. This is already effectively what happens because Status_Monitor assembles from individual regs, but formalise it by synchronising the individual flag regs into SCK and assembling the word on the SCK side. This eliminates any multi-bit coherence concern.

### Verdict
**Good baseline.** Low risk, low area, fixes the staleness problem. Suitable if you're comfortable with clear-on-read.


---


## Option B: Explicit MCU-cleared flags (write-to-clear)

### Concept
Flags are **set** by hardware and **cleared only by the MCU writing to status-clear register(s)**. The MCU writes a mask of the bits it wants to clear (write-1-to-clear, W1C).

### How it works
1. Status_Monitor sets flags as today (sticky, on SAMPLE_CLK)
2. A new `status_clear` register lives in the SCK domain. MCU writes a W1C mask to it
3. The W1C pulse is synchronised into SAMPLE_CLK, and only the written bits are cleared
4. INT remains high until the MCU explicitly clears the offending flags
5. Status can be read at any time via a normal register read (RDREG to address `0x24`) — it doesn't auto-clear on read

### Changes required
- Add a virtual read-only register address for status (e.g. `0x24`/`0x25` for the 14-bit word)
- Add W1C register address(es) (e.g. `0x26`/`0x27`) in Command_Interpreter
- Synchronise the per-bit clear pulses from SCK to SAMPLE_CLK
- Remove `status_sent` feedback path
- Status can still optionally be piggy-backed on the first word, but it is no longer the clearing mechanism

### Pros
- **No lost events**: a flag stays set until the MCU explicitly acknowledges it
- **Deterministic**: the MCU controls exactly when flags clear, which simplifies firmware state machines
- **Safety-critical friendly**: common pattern in medical/automotive ICs (interrupt status register + interrupt clear register)
- **Simpler CDC for the clear path**: single-bit pulses synchronised individually, well understood
- INT behaviour is clean: asserted until MCU clears, no ambiguity about whether the read "counted"

### Cons
- Slightly more SPI overhead: the MCU must do an extra write transaction to clear flags (but this is one 16-bit SPI word, ~1.6 us at 10 MHz — negligible vs the 125 us sample period)
- Marginally more logic (W1C register + sync FFs for clear pulses)

### CDC detail
- **Set path** (SAMPLE_CLK → SCK): each flag is a single-bit sticky register; synchronise individually with 2-FF. Safe because sticky means the signal holds for many SCK cycles
- **Clear path** (SCK → SAMPLE_CLK): W1C write generates a per-bit pulse; stretch it to 2 SAMPLE_CLK cycles using a toggle-handshake or pulse-stretch. At 8 kHz SAMPLE_CLK and 10 MHz SCK, one SCK pulse is ~12.5 us in SAMPLE_CLK terms, so a simple 2-FF sync of the stretched pulse is reliable

### Verdict
**Recommended approach.** Clean, deterministic, safety-friendly, minimal area overhead. This is the standard pattern in production ASICs with interrupt controllers.


---


## Option C: Status bits embedded in each FIFO frame

### Concept
Widen the FIFO to e.g. 142 bits (128 data + 14 status) and store a snapshot of the status word alongside each frame of ADC data. The MCU reads status as part of the data stream.

### Changes required
- FIFO memory width: 128 → 142 bits (+10.9% area for the FIFO SRAM/flops)
- Write side: latch status bits alongside the frame on LASTWORD
- Read side: Command_Interpreter unpacks and serves the extra bits
- SPI protocol change: RDDATA now returns 9 words instead of 8 (or a 9th "status" word), or the extra bits are packed into unused bits of an existing word

### Pros
- Every frame has a **time-correlated status snapshot**: the MCU knows exactly which frame was affected by which fault
- No separate status-read transaction needed
- Eliminates the "stale by one transaction" problem entirely
- Very useful for post-hoc data integrity analysis (e.g. "was channel 3 saturated during this specific sample?")

### Cons
- **+11% FIFO area** — significant when FIFO size is already constrained
- Makes the FIFO and SPI protocol more complex
- Status bits are mostly "slow" events (saturation, overflow) — having per-frame granularity is arguably overkill for most flags
- Does not eliminate the need for an interrupt mechanism (you still need INT to wake the MCU, and the MCU still needs to know whether to act *before* reading the FIFO)
- Does not help with flags that occur *between* frames

### Verdict
**Valuable for safety-critical audit trail, but not a replacement for a proper interrupt/status register.** Consider this as a *complement* to Option B in a future revision, not as the primary status mechanism. The area cost is hard to justify in V1.


---


## Option D: Dedicated status register read (RDSTAT command)

### Concept
Add a new SPI command opcode (e.g. `RDSTAT`) that reads the current status word in a dedicated transaction, separate from data or register reads. Status is NOT piggy-backed on other commands.

### Changes required
- Reserve one of the 4 command opcode slots (or add a special address under RDREG) for status reads
- Command_Interpreter returns the synchronised status word when this command is received
- Optionally: combine with W1C (Option B) so RDSTAT reads status, and a WRSTAT clears it

### Pros
- Clean separation of concerns: data reads don't carry status baggage
- MCU can poll status without side effects
- Compatible with W1C clearing

### Cons
- Uses an SPI transaction just for status (minor overhead)
- Alone, doesn't solve the stale/clear problem — combine with Option B

### Verdict
**Nice-to-have for protocol cleanliness**, but adds little value over reading status from a virtual register address (which you already support via RDREG). Not worth a dedicated opcode unless you're redesigning the command set.


---


## Option E: Status in MISO idle bits (zero-overhead)

### Concept
While the MCU is clocking out a command byte (first 8 bits of a transaction), MISO is normally idle/don't-care. Use those bits to send a live status snapshot.

This is effectively what you do today (status on the first word), but formalised: the status is *always* on the first 16 bits of MISO regardless of the command type.

### Pros
- Zero extra SPI transactions; zero extra latency
- Status is as fresh as possible (loaded when CS drops or on first SCK edges)

### Cons
- Firmware must always capture the first word of every transaction and parse it as status — even during data bursts
- Limited to 16 bits (fine for current 14-bit status)
- Doesn't address the clearing mechanism — still needs W1C or clear-on-read

### Verdict
**This is what you already do.** Keep it as a convenience mechanism, but pair it with W1C (Option B) for the clearing side.


---


## Recommended Architecture

Combine the best elements:

### Primary: Option B (W1C status register)
- Status flags are set by hardware, cleared only by MCU writing a W1C mask
- INT pin reflects `|status[12:0]` (unchanged)
- MCU wakes on INT or DATA_RDY, reads status via RDREG (virtual address), clears via WRREG (W1C address)

### Secondary: Keep status on first SPI word (Option A/E)
- Continue piggy-backing status on the first word of every transaction as a convenience
- This gives the MCU a "free" status peek on every data read without an extra transaction
- But this read does **not** clear flags — only the explicit W1C clears them

### Future (V2): Option C (per-frame status in FIFO)
- If the design moves toward safety certification, embed a condensed status snapshot (e.g. 8 bits: SAT summary, OVF, UDF) per frame
- Defer this until FIFO area budget is finalised

### Implementation summary

```
MCU wakes (INT or DATA_RDY)
  |
  v
SPI transaction: any command
  - First word on MISO = live status snapshot (informational, no side effects)
  |
  v
MCU reads status detail: RDREG 0x24 (status[7:0]), RDREG 0x25 (status[13:8])
  - Non-destructive read, can be repeated
  |
  v
MCU clears flags: WRREG 0x26/0x27, write mask of bits to clear (W1C)
  - `0x26` clears status[7:0] (SAT bits)
  - `0x27` clears status[13:8] using bits [5:0] of the written byte
  - INT de-asserts when all actionable flags are cleared
```

### Register map additions

| Address | Name       | Access | Description                              |
|---------|------------|--------|------------------------------------------|
| 0x24    | STATUS_LO  | R      | Status bits [7:0] (SAT[7:0])            |
| 0x25    | STATUS_HI  | R      | Status bits [13:8] (ADC_OVF, FIFO_OVF, FIFO_UDF, ANALOG_RST, CFGCHNG, ENSAMP) |
| 0x26    | STATUS_CLR_LO | W1C | Write 1 to clear SAT bits [7:0] |
| 0x27    | STATUS_CLR_HI | W1C | Write 1 (bits [5:0]) to clear status[13:8] |


### CDC approach for W1C

```
SCK domain                          SAMPLE_CLK domain
-----------                         ------------------
MCU writes 0x26/0x27      -->   req/ack toggle + 2-FF mask sync   -->   clear_pulse + clear_mask
with mask byte(s)                                               |
                                                                v
                                              if (clear_pulse && clear_mask[n]) flag[n] <= 0
                                              if (event[n])       flag[n] <= 1
                                              (set has priority over clear to avoid
                                               losing an event that arrives in the
                                               same cycle as the clear)
```

The clear pulse from SCK is very wide relative to SAMPLE_CLK (one SCK cycle = ~100 ns; one SAMPLE_CLK cycle = 125 us), so a simple 2-FF synchroniser will reliably capture it. No handshake needed.


### What this buys you for safety

1. **No lost events**: flags persist until explicitly cleared
2. **Deterministic MCU state machine**: MCU always knows what it has and hasn't dealt with
3. **Audit trail**: MCU can log which flags it saw and when it cleared them
4. **INT is meaningful**: stays asserted until the MCU has actually processed the fault
5. **Set-priority-over-clear**: if an event re-fires in the same cycle as a clear, the flag stays set — the MCU will see it next time
6. **Per-frame status (future)**: can be added in V2 without changing the interrupt architecture


### Area cost estimate

- W1C register: ~14 FFs (clear mask) + ~14 FFs (2-FF sync) + clear logic = ~30 FFs
- Remove `status_sent` feedback path: saves ~4 FFs
- Net: ~26 extra FFs — negligible relative to FIFO and config register area
