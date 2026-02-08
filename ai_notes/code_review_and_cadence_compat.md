# Code Review: Consistency, Functional Issues, and Cadence Compatibility

---

## 1. Critical: Duplicate Module Definition

**File:** `source/Status_Clear_CDC.v`

The entire `Status_Clear_CDC` module is defined **twice** in the same file (lines 1–67 and again lines 69–135). This will cause a **fatal error** in any simulator or synthesis tool.

**Fix:** Delete the second copy (lines 69–137).

---

## 2. Critical: Testbenches with No SCK Clock — Command_Interpreter and W1C E2E

### 2a. `tb_req_block_Command_Interpreter.v` — SCK never toggles

The testbench initialises `SCK = 1` and **never toggles it**. The `Command_Interpreter` module uses `always @(posedge SCK ...)` for its state machine, register write logic, status sync FFs, and ack sync FFs. Without a toggling SCK:

- The state machine is stuck in `IDLE` forever (after reset).
- `wr_en_reg` never asserts (the WRITE_REG state is never entered).
- `status_sync` is never updated (stays at reset value of 0).
- All tests are comparing against reset/initial values, not against actual DUT behaviour.

**Impact:** Every test in this testbench is meaningless — results are coincidental or wrong.

**Fix:** Add a free-running SCK clock:
```verilog
initial begin
    SCK = 1;
    forever #(SCK_PERIOD/2) SCK = ~SCK;
end
```
Then rewrite the test stimulus to drive `byte_rcvd`, `word_rcvd`, `cmd_byte`, `data_byte` synchronously to SCK edges (as the real `spiCore` would).

### 2b. `tb_req_status_w1c_end_to_end.v` — same SCK issue

`SCK = 1;` and never toggled. The `Command_Interpreter` inside this testbench is equally dead. The `spi_rdreg` and `spi_wrreg` tasks set `byte_rcvd`/`word_rcvd` with `#(SCK_PERIOD)` delays, but without SCK edges, the CIM never processes them.

**Fix:** Same as 2a — add a free-running SCK clock and align stimulus to SCK edges.

---

## 3. Consistency Issues Between Source Files

### 3a. `spiCore.v` uses old-style port declarations

All other modules use ANSI-style port declarations (`input wire ...` in the port list). `spiCore.v` uses the Verilog-1995 style (ports listed by name, then declared separately in the body). This is functionally fine but inconsistent. More importantly:

- It uses `(* keep = 1 *)` which is a synthesis attribute. Some Cadence tools accept it but it's implementation-specific. See Cadence section below.

### 3b. `spiCore.v` counter width mismatch

Line 80: `bitcnt <= bitcnt + 16'h1;` — `bitcnt` is 4 bits wide but the literal is 16 bits. This works but is poor practice and generates width-mismatch warnings in Cadence Xcelium. Should be `4'h1` or `1'b1`.

### 3c. `Register_CRC.v` — `NRST` input is declared but never used

The module takes `NRST` as an input but has no reset logic (it's purely combinational). This will produce an "unused port" warning. Either remove the port or add a comment/lint waiver.

### 3d. `Temperature_Buffer.v` — `ATMCHSEL` input no longer needed

`ATMCHSEL[9:0]` is still a port and only consumed by `wire _unused_atmchsel = ^ATMCHSEL;`. This is a leftover from the old dual-temp design. Consider removing the port entirely, which also simplifies the TLM instantiation. If kept, add a formal lint waiver comment.

### 3e. TLM declares `spi_tx_buff` (line 150) but never uses it

The SPI's tx_buff is driven by `cim_tx_buff` directly. The wire `spi_tx_buff` is dead. Remove it.

### 3f. TLM declares `reg_chsel` (line 220) but never uses it

`wire [7:0] reg_chsel;` is declared but never assigned or read. Remove it.

### 3g. TLM: `cfg_chnge_sync` (line 177) driven but never consumed

The CDC output `cfg_chnge_sync` is wired but goes nowhere. It's tied to `1'b0` inside `CDC_sync` anyway. Consider removing both the CDC output and the TLM wire, or implementing it properly.

### 3h. TLM: `phase` wire (line 203) is driven but never consumed

The divider's `phase` output is captured but nothing reads it. If it's meant to be a debug/status signal, expose it or document why it's present.

### 3i. `ATM_Control.v` still has old 10-bit temperature toggle logic

The `ATM_Control` module still has the old temperature interleaving code on lines 106–120 that alternates `ATMCHSEL[9:8]` between `2'b01` and `2'b10`. This is **inconsistent** with:
- The refactor plan (reduce ATMCHSEL to 8 bits, use ENMONTSENSE_sync for temp select)
- The updated `Temperature_Buffer` (one-shot capture on ENMONTSENSE_sync rising edge)

Currently, when `ENMONTSENSE_sync` is high, `ATM_Control` keeps toggling the ADC between two temperature inputs and `Temperature_Buffer` captures only the first result (one-shot). The ADC then wastes power running conversions whose results are discarded.

**Note:** This is a planned-but-not-yet-implemented refactor. The code is internally consistent (it still compiles and functions with the old 10-bit behavior) but doesn't match the design intent from the ATMCHSEL refactor plan.

---

## 4. Functional Issues (Would Cause Incorrect Behavior)

### 4a. `tb_top_level_integration.v` — references non-existent modules

The testbench instantiates `dummy_ADC`, `dummy_Mux`, and `spi_master_bfm` but only `spi_master_bfm.v` exists in the testbenches directory. `dummy_ADC` and `dummy_Mux` are missing entirely. This testbench **cannot elaborate**.

**Fix:** Either create these modules or mark this testbench as incomplete/non-functional.

### 4b. `tb_top_level_integration.v` — invalid literal `16'hT111`

Lines 102–103: `16'hT111` and `16'hT222` are not valid hex. `T` is not a hex digit. This is a **syntax error**.

### 4c. `tb_top_level_integration.v` — TLM instantiation missing many ports

The TLM instantiation only connects `HF_CLK`, `RESETN`, `CS`, `SCK`, `MOSI`, `MISO`, `RESULT`, `DONE`, `ATMCHSEL`, `nARST`. Dozens of output ports (all the config outputs, `DATA_RDY`, `INT`, `SAMPLE_CLK`, all `REG_xx`, etc.) are unconnected. While Verilog allows this, Cadence Xcelium will produce many warnings, and any checks that depend on those signals will fail. It's also missing **inputs**: `ADCOVERFLOW`, `SATDETECT`, `SCANEN`, `SCANMODE`.

### 4d. FIFO: `read_ptr_sync_bin` declared as `reg` but driven combinationally

Line 30: `reg [ADDR_WIDTH-1:0] read_ptr_sync_bin;` is driven by an `always @(*)` block. This is technically fine in simulation but some lint tools flag it. Consider changing to `wire` with a continuous assign, or leave as-is (Cadence Xcelium handles it).

### 4e. FIFO: `frame_count` and `frames_available` are `reg` driven combinationally

Same pattern as 4d. Functionally correct but generates lint warnings.

### 4f. Legacy testbenches in testbenches directory

`tb_fifo.v`, `tb_fifo_validate.v`, and `gated_burst_tb.v` appear to be old/legacy testbenches. They may reference older module port lists and could fail to elaborate. Consider either updating or archiving them.

---

## 5. CDC / Timing Concerns (Not Bugs, But Worth Noting)

### 5a. Command_Interpreter synchronizes a 14-bit `status` bus with a 2-FF chain

`status_sync[0] <= status; status_sync[1] <= status_sync[0];` — this is a multi-bit 2-FF sync, which is not safe for independent bits that can change on different cycles. However, because these are sticky flags in the HF_CLK domain and SCK is much faster, the practical risk is very low. For formal CDC verification (e.g., Cadence Conformal), each bit should be synchronized independently, or a gray-coded / handshake approach used.

### 5b. FIFO crosses `ENSAMP_sync` from HF_CLK domain into SCK domain unsynchronised

Line 113: `DATA_RDY = ... && ENSAMP_sync;` and line 197: `else if (!ENSAMP_sync)` — `ENSAMP_sync` is in the HF_CLK/SAMPLE_CLK domain but is being used on `posedge SCK`. This is a **CDC violation**. It should be synchronized into the SCK domain with a 2-FF synchronizer.

### 5c. FIFO reads `mem[read_ptr]` on SCK domain but `mem` is written on SAMPLE_CLK domain

Line 205: `ADC_data <= mem[read_ptr];` — this is a cross-domain memory read. The gray-code pointer synchronization makes this safe in practice (the read pointer only advances after the write pointer has been stable), but formal CDC tools will flag it.

### 5d. Status_Monitor: `ADCOVERFLOW` is used directly without synchronization

In `Status_Monitor.v` line 79: `if (ADCOVERFLOW) adc_ovf_flag <= 1'b1;` — `ADCOVERFLOW` comes from the analog domain (an external pin) but is used on `posedge HF_CLK` without a 2-FF synchronizer. It should be synchronized in `CDC_sync` like `SATDETECT` is.

---

## 6. Cadence Tool Compatibility Changes

### 6a. `$dumpfile` / `$dumpvars` — not supported by Xcelium natively

All testbenches use `$dumpfile("simulation/xxx.vcd")` and `$dumpvars`. Cadence Xcelium uses **SHM** format natively for SimVision, not VCD.

**Fix options:**
- Replace with `$shm_open("simulation/xxx.shm"); $shm_probe("ASM");` for Cadence tools
- Or wrap in a `` `ifdef CADENCE `` / `` `else `` guard:

```verilog
`ifdef CADENCE
    initial begin
        $shm_open("simulation/waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/waves.vcd");
        $dumpvars(0, tb_name);
    end
`endif
```

Alternatively, Xcelium does support VCD via `-access +rwc` flag, but SHM is faster and what SimVision expects.

### 6b. `$countones` system function

Used in `tb_req_block_ATM_Control.v`. `$countones` is a SystemVerilog function (IEEE 1800). If you compile with Xcelium in **Verilog-2001 mode** (`-v` flag or `.v` extension with strict mode), this will fail.

**Fix:** Either compile with SystemVerilog mode (`xrun -sv`) or replace with a manual popcount:

```verilog
function integer countones;
    input [9:0] val;
    integer k;
    begin
        countones = 0;
        for (k = 0; k < 10; k = k + 1)
            countones = countones + val[k];
    end
endfunction
```

### 6c. `$error` system task

Used extensively in testbenches. `$error` is a SystemVerilog-2009 task. In pure Verilog-2001 mode it doesn't exist.

**Fix:** Either compile with `-sv` or replace with `$display("ERROR: ...")` (losing the severity semantics).

### 6d. `$stop` vs `$finish`

Testbenches use `$stop` which halts simulation and drops to the interactive debugger. This is correct for SimVision interactive use. If you want batch-mode runs (e.g., in a regression), use `$finish` instead, or add a `+define+BATCH` guard.

### 6e. `(* keep = 1 *)` attribute in `spiCore.v`

This is a Synopsys-style synthesis attribute. Cadence Genus/RTL Compiler uses `(* syn_keep = 1 *)` or the `dont_touch` constraint. For simulation it's ignored, but for synthesis you may need to translate it.

### 6f. `/* cadence preserve_sequential */` pragma in `spiCore.v`

Line 46: This is a legacy Cadence pragma. It's recognized by older Cadence tools but modern Genus prefers `(* preserve *)` or SDC constraints. It won't cause errors but may not have the intended effect in newer tool versions.

### 6g. `$clog2` in `FIFO.v`

`$clog2` is IEEE 1364-2005 (Verilog-2005). Cadence Xcelium supports it. Older Cadence tools (e.g., NC-Sim < 14.x) may not. If targeting very old tools, replace with a parameter function. For Xcelium this is fine.

### 6h. Testbench `initial` blocks with `forever` — potential Xcelium scheduling

The `tb_req_block_Command_Interpreter.v` ack model uses `initial begin ... forever begin ... #1; ...` with `wait(NRST)`. This is fine in Xcelium but the `#1` busy-wait is inefficient. Consider using `@(posedge ...)` waits instead for cleaner scheduling.

### 6i. No `timescale` on source files

None of the source `.v` files have a `` `timescale `` directive. The testbenches have `` `timescale 1ns / 1ps ``. In Xcelium, the compilation order matters — if a source file is compiled before any testbench, it inherits the simulator default timescale (usually `1ns/1ns`). This can cause mismatches.

**Fix:** Add `` `timescale 1ns / 1ps `` to every source file, or use the Xcelium `-timescale 1ns/1ps` command-line flag to set a global default.

### 6j. File compilation order / filelist

Cadence tools typically use a `-f filelist.f` to specify compilation order. You'll need to create one. See Section 8 below.

### 6k. Xcelium access flags

For waveform probing and hierarchical access in testbenches, you'll need to compile with:
```
xrun -access +rwc ...
```
Without this, `$dumpvars` (or `$shm_probe`) and hierarchical signal references may fail.

### 6l. Encounter (Innovus) — synthesis directives

If targeting Cadence Innovus for place-and-route, the RTL needs to have been synthesized first (typically with Genus). The `(* keep = 1 *)` and `/* cadence preserve_sequential */` pragmas in `spiCore.v` may need updating. Genus uses `set_dont_touch` and `set_attribute` SDC/TCL commands rather than inline pragmas for modern flows.

---

## 7. Summary: Priority Fixes

| Priority | Issue | File(s) | Category |
|----------|-------|---------|----------|
| **P0 - Blocker** | Duplicate module definition | `Status_Clear_CDC.v` | Source |
| **P0 - Blocker** | SCK never toggles — all tests invalid | `tb_req_block_Command_Interpreter.v` | Testbench |
| **P0 - Blocker** | SCK never toggles — all tests invalid | `tb_req_status_w1c_end_to_end.v` | Testbench |
| **P0 - Blocker** | Invalid hex literal `16'hT111` | `tb_top_level_integration.v` | Testbench |
| **P0 - Blocker** | Missing `dummy_ADC`/`dummy_Mux` modules | `tb_top_level_integration.v` | Testbench |
| **P1 - Should fix** | Dead wires (`spi_tx_buff`, `reg_chsel`, `cfg_chnge_sync`, `phase`) | `TLM.v` | Source |
| **P1 - Should fix** | `ADCOVERFLOW` not synchronized to HF_CLK | `Status_Monitor.v` / `CDC_sync.v` | Source (CDC) |
| **P1 - Should fix** | FIFO uses `ENSAMP_sync` on SCK domain without sync | `FIFO.v` | Source (CDC) |
| **P1 - Should fix** | Add `timescale` to source files or use global flag | All source `.v` | Cadence |
| **P1 - Should fix** | Wrap `$dumpfile`/`$dumpvars` for Cadence or switch to SHM | All testbenches | Cadence |
| **P1 - Should fix** | `$countones` requires SystemVerilog | `tb_req_block_ATM_Control.v` | Cadence |
| **P1 - Should fix** | `$error` requires SystemVerilog | All testbenches | Cadence |
| **P2 - Nice to have** | Unused port `NRST` in `Register_CRC` | `Register_CRC.v` | Cleanup |
| **P2 - Nice to have** | Unused port `ATMCHSEL` in `Temperature_Buffer` | `Temperature_Buffer.v` | Cleanup |
| **P2 - Nice to have** | `spiCore.v` counter width mismatch | `spiCore.v` | Cleanup |
| **P2 - Nice to have** | ATM_Control still has old temp toggle logic | `ATM_Control.v` | Incomplete refactor |
| **P2 - Nice to have** | Create `filelist.f` for Cadence compilation | New file | Cadence |
| **P2 - Nice to have** | Legacy testbenches may be stale | `tb_fifo.v`, `gated_burst_tb.v` | Cleanup |

---

## 8. Recommended Cadence `filelist.f`

```
// Global timescale (or add `timescale to each file)
-timescale 1ns/1ps

// Access flags for waveform/debug
-access +rwc

// Source files
source/spiCore.v
source/Command_Interpreter.v
source/Configuration_Registers.v
source/Register_CRC.v
source/CDC_sync.v
source/Status_Clear_CDC.v
source/Status_Monitor.v
source/Dual_phase_gated_burst_divider.v
source/ATM_Control.v
source/FIFO.v
source/Temperature_Buffer.v
source/TLM.v
```

Testbench-specific filelists (one per testbench, add to the above):
```
// For unit testbenches (compile with -sv for $error/$countones support):
// xrun -sv -f filelist.f testbenches/tb_req_block_ATM_Control.v

// For W1C E2E:
// xrun -sv -f filelist.f testbenches/tb_req_status_w1c_end_to_end.v

// For top-level integration (BROKEN - needs dummy_ADC/dummy_Mux):
// testbenches/spi_master_bfm.v
// testbenches/tb_top_level_integration.v
```

### Xcelium run example
```bash
# Unit testbench (e.g. CDC_sync)
xrun -sv -timescale 1ns/1ps -access +rwc \
     -f filelist.f \
     testbenches/tb_req_block_CDC_sync.v \
     -top tb_req_block_CDC_sync

# With SHM waveform dumping (add +define+CADENCE if using ifdef guards)
xrun -sv -timescale 1ns/1ps -access +rwc \
     +define+CADENCE \
     -f filelist.f \
     testbenches/tb_req_block_CDC_sync.v \
     -top tb_req_block_CDC_sync
```
