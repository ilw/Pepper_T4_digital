# Area Reduction Analysis — Pepper T4 Digital

## Register Bit Budget (approximate)

| Block                          | Reg bits | Notes                                          |
|-------------------------------|----------|------------------------------------------------|
| **FIFO (mem)**                | **2048** | 16 frames x 128-bit = dominant contributor     |
| Configuration_Registers       | 288      | 36 x 8-bit register file                       |
| Command_Interpreter           | ~156     | State machine, CRC, status sync, tx_buff       |
| CDC_sync                      | ~124     | 2-FF synchronizers for ~15 multi-bit signals   |
| spiCore                       | ~48      | Shift registers, bit counter                   |
| Status_Clear_CDC              | ~36      | Toggle synchronizer + mask latches             |
| Status_Monitor                | ~36      | Sticky flags + crccfg_prev[15:0]               |
| ATM_Control                   | ~27      | Channel mux, prediction counter, pipeline      |
| Dual_phase_gated_burst_divider| ~18      | Clock divider counters                         |
| Temperature_Buffer            | ~18      | 16-bit capture register + control              |
| TempSense_Control             | ~5       | One-shot FSM                                   |
| TLM (DONE_QUAL)               | ~1       | discard_first_done                             |
| **Total**                     | **~2805**|                                                |

### FIFO = 73% of all register area

The FIFO memory array at 2048 bits utterly dominates. Everything else combined is ~757 bits.

---

## Area Reduction Opportunities (ranked by impact)

### 1. FIFO depth reduction (HIGH IMPACT)

| Depth | Bits  | Saving vs 16 |
|-------|-------|--------------|
| 16    | 2048  | baseline     |
| 8     | 1024  | -1024 (50%)  |
| 4     | 512   | -1536 (75%)  |
| 2     | 256   | -1792 (87%)  |

**Recommendation**: Make `FRAME_DEPTH` easily configurable (it already is a parameter).
At 8kHz SAMPLE_CLK with 8 channels, one frame arrives every 1ms.
- Depth 4 = 4ms buffer, enough for typical MCU wake + SPI burst at 10MHz
- Depth 2 = absolute minimum, requires very fast MCU response

### 2. Remove Register_CRC (MEDIUM IMPACT)

`Register_CRC` is pure combinational but synthesizes to a **large XOR tree**
(16-bit CRC over 288 config bits = ~32 XOR gates per output bit x 16 bits).
It also forces `Status_Monitor` to keep a 16-bit `crccfg_prev` register
for change detection.

**Total saving**: ~500-800 gate equivalents (XOR tree) + 16 register bits.

Already requested by user — implement via `define or parameter guard.

### 3. Reduce CDC_sync register count (MEDIUM IMPACT)

Many multi-bit signals go through 2-FF synchronizers individually.
Consider whether all truly need CDC:

| Signal group          | Width | 2-FF cost | Question                              |
|-----------------------|-------|-----------|---------------------------------------|
| PHASE1DIV1_sync       | 12    | 24 FFs    | Only changes when not sampling?       |
| PHASE2COUNT_sync      | 10    | 20 FFs    | Only changes when not sampling?       |
| CHEN_sync             | 8     | 16 FFs    | Only changes when not sampling?       |
| AFERSTCH_sync         | 8     | 16 FFs    | Only changes when not sampling?       |
| SATDETECT_sync        | 8     | 16 FFs    | Needed per-cycle?                     |
| ADCOSR_sync           | 4     | 8 FFs     | Only changes when not sampling?       |
| PHASE1COUNT_sync      | 4     | 8 FFs     | Only changes when not sampling?       |

If config registers are only written while `ENSAMP=0`, you could **latch
them once on the ENSAMP rising edge** instead of continuously synchronizing.
This would replace ~108 FFs (2-FF chains) with ~54 FFs (single capture
register) — saving ~54 FFs.

### 4. Simplify Command_Interpreter CRC (LOW-MEDIUM IMPACT)

The `crc_next` function computes CRC-16-CCITT over 16 bits per call using
a 16-iteration loop. This unrolls to ~256 XOR/AND gates. If the CRC feature
is cut (see #2), the `crc_value` register (16 bits) and all CRC logic can
be removed from `Command_Interpreter` too.

### 5. Reduce Configuration_Registers (LOW IMPACT)

Currently 36 x 8-bit = 288 bits. If any registers are truly unused or can
be hardwired, each removed register saves 8 FFs. But most seem to be
actively used by the analog, so saving here is limited.

### 6. Status_Monitor crccfg_prev removal (LOW IMPACT)

If Register_CRC is cut, `crccfg_prev[15:0]` (change detection) and the
`cfgchng_flag` logic can also be removed — saves 16 FFs + comparator.

---

## Summary of quick wins

| Change                              | Approx saving (FFs) | Complexity |
|-------------------------------------|---------------------|------------|
| FIFO depth 16→4                     | 1536                | Trivial    |
| FIFO depth 16→8                     | 1024                | Trivial    |
| Remove Register_CRC + CIM CRC      | ~48 FFs + XOR trees | Easy       |
| CDC latch-on-enable instead of sync | ~54                 | Moderate   |
| Remove crccfg_prev when no CRC     | 16                  | Easy       |

**Biggest single win**: FIFO depth. Going from 16→4 frames saves more area than
removing every other block combined.
