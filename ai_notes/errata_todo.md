# Errata & TODOs — Pepper T4 Digital

## ERR-ADC-STARTUP-DONE — Immediate DONE on first clock after enable

**Status: RESOLVED (DONE_QUAL mitigation in TLM.v)**

### Description

The `ns_sar_v2` decimator produces an **immediate DONE pulse** on the very
first SAMPLE_CLK rising edge after `nARST` deasserts.

#### Root cause (from netlist analysis)

- `state[4:0]` is async-cleared to `0` on reset.
- `state[5]` (phase toggle) is async-**set** to `1` on reset
  (`DFSNQD1BWP7T` flip-flop with `SDN(nARST)`).
- `count_reset` fires when `state[4:0] == 0` (combinational carry-out).
- `completion_flag = count_reset AND state[5]` = `1 AND 1` = **immediately true**.
- `CIC_DONE` flip-flop captures `trigger_b` → **DONE = 1** on the first posedge.

At this point the CIC integrators have not yet accumulated any data, so the
associated RESULT value is invalid (zero / noise).

#### Behaviour by mode

| Mode       | First posedge after nARST | Steady-state period |
|------------|---------------------------|---------------------|
| SAR (OSR=0)| DONE = 1 (always high)    | 1 cycle             |
| NS  (OSR>0)| DONE = 1 (startup pulse)  | 4*OSR + 2 cycles    |

After the startup DONE, the counter reloads to `{OSR, 1'b0}` = `2*OSR` and
runs two half-windows of `2*OSR + 1` cycles each before the next DONE.

### Mitigation — `DONE_QUAL` in TLM.v

A qualification register (`discard_first_done`) suppresses the first DONE
after every nARST assertion:

```verilog
reg discard_first_done;
always @(posedge SAMPLE_CLK or negedge nrst_sync) begin
    if (!nrst_sync)
        discard_first_done <= 1'b1;
    else if (!nARST)
        discard_first_done <= 1'b1;
    else if (discard_first_done && DONE)
        discard_first_done <= 1'b0;
end
assign DONE_QUAL = DONE & ~discard_first_done;
```

All downstream consumers (FIFO, TempSense_Control, Temperature_Buffer) are
connected to `DONE_QUAL` rather than raw `DONE`.

### ATM_Control alignment

ATM_Control does **not** use DONE; it uses predictive counting based on
`OSR_sync`.  Its counter starts from 0 on the same posedge as the ADC's
startup DONE, so the first full-window terminal naturally aligns with the
mock's second DONE (= first valid DONE after DONE_QUAL passes).

### Mock ADC model

The behavioral mock (`ns_sar_v2_mock.v`) now replicates this behaviour:
a combinational `startup_done` signal fires on the first active posedge
after reset, exactly matching the real ADC's `CIC_DONE` behaviour.  The
unit testbench (`tb_req_block_ns_sar_v2_mock.v`) explicitly checks for this
startup pulse and verifies the subsequent steady-state cadence.
