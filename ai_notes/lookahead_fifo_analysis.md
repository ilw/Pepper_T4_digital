# Look-Ahead FIFO Conversion Analysis

## Summary
Converting the FIFO from **pop-to-read** to **look-ahead** is **moderate difficulty**. The core FIFO change is small (~15 lines), but there are subtle interactions with zero-clearing, CDC, and the Command Interpreter that need careful handling.

**Overall Verdict: Feasible, recommended.**

---

## 1. FIFO.v — Core Read Logic Change

### Current Behavior (Pop-to-Read)
```verilog
// ADC_data only updates when FIFO_POP fires
if (FIFO_POP) begin
    if (frames_available) begin
        ADC_data <= mem[read_ptr];
        read_ptr <= read_ptr + 1;
    end else begin
        ADC_data <= 128'h0;
    end
end
```

### Proposed Behavior (Look-Ahead)
```verilog
// ADC_data continuously reflects the frame at read_ptr
if (frames_available)
    ADC_data <= mem[read_ptr[ADDR_WIDTH-1:0]];
else
    ADC_data <= 128'h0;

// FIFO_POP only advances the pointer (doesn't load data)
if (FIFO_POP && frames_available) begin
    read_ptr      <= read_ptr + 1'b1;
    read_ptr_gray <= bin_to_gray(read_ptr + 1'b1);
end
```

### Timing Analysis
- **Cycle N**: `FIFO_POP` fires → `read_ptr` advances to N+1
- **Cycle N+1**: `ADC_data` picks up `mem[N+1]` (new frame visible)
- This is **identical timing** to the current design in steady-state (pop loads data on same edge, CIM reads it on next edge).
- **Improvement**: At startup, `ADC_data` already shows Frame 0 as soon as `frames_available` goes high — **no garbage first frame**.

**Difficulty: LOW** — ~15 lines changed in one `always` block.

---

## 2. Clock Domain Crossing Safety

### Is it safe to continuously read `mem[read_ptr]` from SCK when SAMPLE_CLK writes to it?

**Yes** — the existing safety invariant is preserved:

1. The read domain ONLY reads from slots where `write_ptr > read_ptr` (guaranteed by `frames_available` check, which uses the Gray-code-synchronized write pointer).
2. The frame at `read_ptr` was completed by the write domain BEFORE `write_ptr_gray` advanced, and that advance has already propagated through the 2-stage synchronizer.
3. Gray code ensures only one pointer bit changes per increment → no multi-bit glitch risk on the synchronized pointers.

**The only change**: `mem[]` is read on *every* SCK edge (vs. only on `FIFO_POP` edges currently). This doesn't affect CDC correctness — the memory read is already cross-domain. It slightly increases read-port activity in synthesis but has no functional impact.

**Difficulty: NONE** — no CDC changes required.

---

## 3. Status Bits (Overflow / Underflow)

### Overflow (Write Domain)
- No change. Overflow is detected in the write domain when `frame_count == FRAME_DEPTH` on `LASTWORD`. Completely independent of read behavior.

### Underflow (Read Domain)
- Current: toggles when `FIFO_POP && !frames_available && ENSAMP_sync`
- Look-ahead: **same logic, no change needed**. `FIFO_POP` on an empty FIFO still toggles the underflow event.

**Difficulty: NONE** — no changes required.

---

## 4. Zero-Clearing Logic (Write Domain)

### Current Mechanism
The write domain zeros out frames after they've been read:
```verilog
if (frame_pop_edge)
    mem[read_ptr_sync_prev_idx] <= 128'h0;
```
Where `read_ptr_sync_prev_idx` is the *previous* read pointer index (one behind the current `read_ptr`), synchronized to `SAMPLE_CLK`.

### With Look-Ahead — Subtle Interaction

**Concern**: With look-ahead, `ADC_data <= mem[read_ptr]` runs every SCK cycle. If the write domain zeros a slot, could `ADC_data` pick up zeros from under it?

**Analysis**: **Safe, but the timing shifts by one slot.**

| Event | `read_ptr` | Slot being read | Slot being zeroed |
|:---|:---:|:---:|:---:|
| Frame N visible | N | Slot N | — |
| FIFO_POP fires | N → N+1 | — | — |
| Next SCK cycle | N+1 | Slot N+1 | — |
| `frame_pop_edge` (SAMPLE_CLK, ~2 cycles later) | N+1 | Slot N+1 | **Slot N** ✓ |

The zeroed slot (N) is always **behind** the currently-read slot (N+1). No race condition.

**However**: There's one edge case. The existing `mem[write_ptr_next] <= 128'h0` (pre-clear on frame advance, line 184) writes to the slot AHEAD of the write pointer. If the FIFO is nearly full and the read pointer is close to the write pointer, this pre-clear could hit a slot the read domain is about to look-ahead into. But this can only happen in an overflow condition (write catching up to read), which is already an error state.

**Difficulty: LOW** — no code changes needed, but worth adding a comment.

---

## 5. Command Interpreter Changes

### Steady-State Streaming — No Change Needed
The CIM's streaming logic works correctly with look-ahead:
1. `ADC_data` already shows Frame N (via look-ahead)
2. CIM reads words 0–7 via `tx_buff_reg = ADC_data[word_counter*16 +: 16]`
3. After word 7: `FIFO_POP` fires → `read_ptr` advances
4. Next SCK cycle: `ADC_data` shows Frame N+1
5. CIM reads words 0–7 of Frame N+1

**The first frame is now valid** — no discard needed.

### Pop-on-CS-High — Needs Consideration

Currently (line 359):
```verilog
if ((state == READ_DATA) && (nstate == IDLE)) begin
    fifo_pop_reg <= 1'b1;  // Pop when CS goes high mid-stream
end
```

**Current behavior**: Pop-on-CS-high loads the next frame into `ADC_data`, so the next RDDATA session starts with valid data. This is a "pre-fetch" that hides the pop-to-read latency.

**With look-ahead**: Pop-on-CS-high would advance `read_ptr`, **consuming a potentially unread frame**. If the user read words 0–3 then raised CS, the remaining words 4–7 are lost AND the pointer advances past them.

**This is actually the same behavior as today** (the current pop also consumes the partial frame). But with look-ahead, the pop is no longer needed for pre-fetching — it's only needed for "consume what I started reading."

**Options**:
1. **Keep as-is**: Pop-on-CS-high still consumes partial frames. Semantically identical to current design. Simplest.
2. **Remove pop-on-CS-high**: Don't advance the pointer if CS goes high mid-stream. The partial frame remains at `read_ptr` and is re-presented on the next `RDDATA`. This is arguably better behavior but changes the data flow contract.

**Recommendation**: Keep as-is (Option 1) for minimal behavioral change.

**Difficulty: NONE to LOW** — no changes required if keeping Option 1.

---

## Summary Table

| Area | Changes Needed | Difficulty | Risk |
|:---|:---|:---:|:---:|
| **FIFO.v read logic** | Rewrite read `always` block (~15 lines) | Low | Low |
| **CDC pointers** | None | None | None |
| **Status bits** | None | None | None |
| **Zero-clearing** | None (add safety comment) | None | Low |
| **Command Interpreter** | None (Option 1) | None | None |
| **Testbenches** | Update expectations (first frame now valid) | Low | Low |

## Existing Tests to Update
- `tb_req_block_FIFO.v` — FIFO block-level tests
- `tb_fifo_validate.v` — FIFO validation
- `tb_top_level_medium.v` — Integration tests with streaming
- `tb_top_level_signoff.v` — Full signoff tests

## Verification Plan
1. Run `tb_req_block_FIFO.v` — confirm no overflow/underflow regressions
2. Run `tb_fifo_validate.v` — confirm data integrity
3. Run `tb_top_level_medium.v` — confirm end-to-end streaming works
4. **New test**: Verify first RDDATA frame contains valid data (not zeros)
