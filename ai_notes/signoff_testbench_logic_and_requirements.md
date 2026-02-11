## Purpose

This note documents the **logic**, **assumptions**, and **requirements mapping** for the signoff-tier top-level testbench family:

- `testbenches/tb_top_level_mock_signoff.v` (runs with mock ADC)
- `testbenches/tb_top_level_signoff.v` (intended for real ADC netlist)

The signoff TB’s intent is to provide **requirements-oriented coverage** (DIG-xx) against the Pepper T4 digital RTL, using a realistic top-level integration setup.

- `TLM` (top-level)
- `ns_sar_v2` mock ADC
- `dummy_Mux` (analog mux model)
- SPI master bit-banging tasks (Mode 3)

Related requirements sources in this repo:

- `pepper_t4_digital_requirements(Pepper T4 requirements).csv`
- `pepper_t4_digital_requirements(pepper_t4_digital_requirements).csv`
- `pepper_t4_digital_requirements(cmd and response list).csv`
- `pepper_t4_digital_requirements(Register map).csv`

---

## Testbench topology (what is instantiated)

### DUT + models

- **DUT**: `TLM dut(...)`
- **ADC model**: `ns_sar_v2 adc_mock(...)`
  - Driven by `SAMPLE_CLK_w` and `nARST_w` from `TLM`
  - Outputs `RESULT` and `DONE` back into `TLM`
- **Analog mux model**: `dummy_Mux mux(...)`
  - Uses `ATMCHSEL` (8-bit one-hot) and `TEMPSEL=ENMONTSENSE_w`
  - Provides deterministic per-channel words and a temperature word

### Pad modeling / tri-state behavior

The TB models the external MISO pad as tri-stated when output-enable indicates “disabled”:

- `MISO_PAD = (OEN_w === 1'b0) ? MISO_CORE : 1'bz;`

And it continuously checks expected behavior when `SCANMODE==0`:

- `CS==1` → expect `OEN_w==1` and `MISO_PAD==Z`
- `CS==0` → expect `OEN_w==0` and `MISO_PAD!=Z`

This is used for **S12** and also as a continuous correctness guard.

---

## SPI stimulus model (critical assumptions)

### SPI mode

The signoff TB uses **SPI Mode 3** semantics (CPOL=1, CPHA=1):

- `SCK` idles high when `CS` is high (`spi_end()` forces `SCK=1`)
- Per bit, TB drives `MOSI`, toggles `SCK 1→0→1`, and samples `MISO_PAD` shortly after the rising edge.

### Word framing (IMPORTANT)

The DUT’s SPI protocol is **word-based** with important multi-word behaviors:

- **RDREG** returns:
  - word0: STATUS
  - word1: REGDATA
  - while `CS` remains low
- **RDDATA** returns:
  - word0: STATUS (command acceptance)
  - word1..word8: 8×16-bit FIFO words (128-bit frame)
  - while `CS` remains low

Therefore, multi-word transactions require **exactly 16 SCK cycles per 16-bit word**.

#### Implementation in `tb_top_level_signoff.v`

The TB uses two transfer primitives:

- `spi_transfer_word16_timed(...)`
  - **exactly 16 SCK cycles**
  - used for **reads** and **bursts** (RDREG second word and all RDDATA words)
- `spi_transfer_word_wr_timed(...)`
  - **16 SCK cycles + one extra trailing rising edge**
  - used only for **WRREG** writes
  - rationale: the current write path expects an additional post-word edge for reliable commit in the SCK domain (matches the project’s current SCK-domain write-latch approach)

Helper tasks:

- `write_reg_timed(addr, data, half_period_ns)` uses `spi_transfer_word_wr_timed`
- `read_reg_timed(addr, half_period_ns, data)` uses `spi_transfer_word16_timed` twice (status then regdata)
- `read_fifo_frame(data128)` uses `spi_transfer_word16_timed` for `C000` + 8 dummy words

---

## Global procedural requirement (system-level)

To guarantee a clean sampling disable (and allow the FIFO’s SCK-domain reset to settle), the system-level recommended protocol is:

- **Do not perform a FIFO read (RDDATA) in the same SPI transaction as disabling sampling** (`ENSAMP=0` write).

In other words:

- transaction A: write `reg 0x23` with ENSAMP=0, end transaction (`CS` high)
- transaction B: later, perform `RDDATA` / other reads

This avoids edge cases where the SCK-domain reset/clear has not yet deterministically taken effect before a read.

---

## Signoff tests S1..S14 (logic + requirements mapping)

The signoff TB records `test_pass[idx]` and prints a summary at the end.

### S1. SPI protocol edge patterns

**Logic**
- Writes/reads a small set of patterns at `reg 0x00` using normal timing (`half_period=50ns`).

**Requirements**
- DIG-4, DIG-5, DIG-6

### S2. SPI at near-max frequency

**Logic**
- Performs register write/read loop at `~15MHz` (half period `33ns`).

**Requirements**
- DIG-7

### S3. Clock divider configurations

**Logic**
- Configures divider registers (`0x20..0x22`) and verifies `SAMPLE_CLK` increments `sample_ctr` while enabled.

**Requirements**
- DIG-8, DIG-37, DIG-38, DIG-39, DIG-40, DIG-45

### S4. Channel enable permutations (subset)

**Logic**
- Sweeps representative `CHEN` values: `0x01, 0x80, 0x55, 0xAA, 0xFF, 0x00`
- For `CHEN=0x00`, verifies ADC is disabled (`nARST` remains low).

**Requirements**
- DIG-29, DIG-33, DIG-34, DIG-35

### S5. OSR sweep (0..15) / DONE period check

**Logic**
- Sweeps OSR codes 0..15 by writing `reg 0x1B` (upper nibble OSR)
- For OSR=0 expects DONE high (SAR mode)
- For OSR>0 measures DONE pulse spacing and checks \( \text{period} = 4\cdot \text{OSR} + 2 \)

**Requirements**
- DIG-36

### S6. Saturation per-channel and multi-channel

**Logic**
- Pulses each `SATDETECT` bit, checks corresponding sticky status bit sets, then clears via W1C.
- Tests a multi-bit pattern (`0xA5`) similarly.

**Requirements**
- DIG-42, DIG-87, DIG-88

### S7. ADC overflow flag (W1C)

**Logic**
- Pulses `ADCOVERFLOW_stim`, checks status bit 8 sets
- Clears via W1C and checks it clears

**Requirements**
- DIG-89

### S8. CRC read (conditional)

**Logic**
- If ``ENABLE_REGISTER_CRC`` is enabled, performs `RDCRC` read and checks for a non-X response.
- If not enabled, test is marked SKIP.

**Requirements**
- DIG-54, DIG-66, DIG-67, DIG-68

### S9. DATA_RDY semantics (threshold / deassert on read)

**Logic**
- Enables sampling with watermark=2
- Expects `DATA_RDY` asserts once threshold reached
- Reads one frame via SPI and expects `DATA_RDY` deasserts afterward

**Requirements**
- DIG-9, DIG-18, DIG-20

### S10. FIFO clear-on-read (backdoor)

**Logic**
- Reads one FIFO frame via SPI
- Then checks internal FIFO memory entries (`dut.u_fifo.mem[0..3]`) have been cleared to zero

**Requirements**
- DIG-24

### S11. Disable mid-frame; no partial frame after re-enable

**Logic**
- Enables sampling, waits mid-frame, disables (`ENSAMP=0`), waits, re-enables
- Reads a frame and checks none of its 16-bit words are zero (i.e. no partial/garbled frame)

**Requirements**
- DIG-31, DIG-32

### S12. Scan pin isolation

**Logic**
- Enables sampling, captures `sample_ctr` progress
- Asserts `SCANEN=1` and `SCANMODE=1`, checks sampling continues (and pad checker remains sane)
- Deasserts scan and disables sampling

**Requirements**
- DIG-11

### S13. Register defaults after reset

**Logic**
- Pulses reset (`RESETN=0→1`)
- Reads all physical regs `0x00..0x23` and expects `0x00`

**Requirements**
- DIG-63

### S14. Continuous sampling endurance

**Logic**
- Runs 50 frame-equivalents
- Reads frames periodically to avoid overflow
- Expects no FIFO overflow status at end

**Requirements**
- DIG-13, DIG-16, DIG-84

---

## Requirements coverage matrix (as designed)

This is the intended mapping used when the signoff tier was planned (DIG IDs marked “Yes” mapped to TB tiers):

- DIG-4: S1
- DIG-5: S1
- DIG-6: S1
- DIG-7: S2
- DIG-8: S3
- DIG-9: S9
- DIG-11: S12
- DIG-13: S14
- DIG-16: S14
- DIG-18: S9
- DIG-20: S9
- DIG-24: S10
- DIG-29: S4
- DIG-31: S11
- DIG-32: S11
- DIG-33: S4
- DIG-34: S4
- DIG-35: S4
- DIG-36: S5
- DIG-37: S3
- DIG-38: S3
- DIG-39: S3
- DIG-40: S3
- DIG-42: S6
- DIG-45: S3
- DIG-54: S8
- DIG-63: S13
- DIG-66: S8
- DIG-67: S8
- DIG-68: S8
- DIG-84: S14
- DIG-87: S6
- DIG-88: S6
- DIG-89: S7

---

## Notes / limitations

- **S10 uses backdoor memory checks** (`dut.u_fifo.mem[]`). This is simulator-friendly in Icarus but is an *implementation-sensitive* check (it assumes “clear-on-read” means physically clearing `mem[]`, not just outputting zero when empty).
- **S11 “no zero words”** is a strong proxy for “no partial frames”, but it can false-fail if valid data words can legitimately be `0x0000` under some configurations. The mock ADC was configured to avoid all-zero results in other tests, but signoff doesn’t explicitly force this for every scenario.
- **Procedural rule** (CS-separated disable/read) should be followed by firmware and by tests that disable sampling and then read FIFO data, to avoid ambiguous timing around FIFO read-side reset and CDC.

