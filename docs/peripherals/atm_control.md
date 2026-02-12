# ATM Control Module

## Overview

The `ATM_Control` module is a **predictive channel sequencer** responsible for cycling through enabled analog channels for the ADC.

Unlike simple sequencers that wait for an ADC "Done" signal to switch channels, the ATM Control block maintains its own internal counter to **predict exactly when the next conversion will begin**. It switches the analog mux *one cycle before* the conversion start, ensuring the analog signal is stable during the acquisition phase.

It also provides pipelined signals (`ATMCHSEL_DATA`, `LASTWORD`) that are aligned with the ADC's data output, facilitating correct data tagging in the FIFO.

---

## Control Sequence

### 1. Triggering
The sequence is enabled by the `ENSAMP_sync` signal.
- **Enable (`ENSAMP_sync = 1`)**: The sequence begins immediately. The first channel selected is the lowest enabled index (e.g., Channel 0).
- **Disable (`ENSAMP_sync = 0`)**: The internal counters and outputs are reset to 0.

### 2. State Machine
The module implements a circular state machine that iterates through the enabled channels specified in `CHEN_sync`:

1.  **Startup**: When enabled, the mux (`ATMCHSEL`) is set to the first enabled channel.
2.  **Conversion Timing**: An internal counter (`cycle_count`) tracks the duration of the current conversion based on the Oversampling Ratio (OSR).
3.  **Predictive Switch**: At the **terminal count** (end of the current conversion window), the logic:
    *   Calculates the **next** enabled channel in a circular fashion (wrapping from Ch7 to Ch0).
    *   Updates `ATMCHSEL` to this new channel immediately.
    *   This ensures the mux is switched and settling *while* the ADC is finishing the previous sample and preparing to acquire the next.
4.  **Data Alignment**:
    *   `ATMCHSEL_DATA` effectively delays `ATMCHSEL` by one cycle. This matches the ADC's internal pipeline (Sample -> Done aligned).
    *   `LASTWORD` is asserted when the *data* corresponding to the highest index channel is valid.

### 3. Conversion Lengths
The duration of each step depends on the `OSR_sync` setting:

| Mode | OSR | Formula | Cycles | Description |
| :--- | :--- | :--- | :--- | :--- |
| **SAR** | 0 | `1` | 1 | Single-cycle sampling (fastest) |
| **NS** | N > 0 | `4*N + 2` | 6, 10, ... | Noise-shaping oversampling |

---

## Timing Diagram

The following WaveDrom diagram illustrates a sequence with **OSR=0 (SAR Mode, 1 cycle/conv)** enabling Ch0, Ch1, and Ch2.

```json
{signal: [
  {name: 'CLK',       wave: 'p........'},
  {name: 'ENSAMP',    wave: '01.......'},
  {name: 'CHEN',      wave: 'x3.......', data: ['0,1,2']},
  {name: 'Counter',   wave: '=.=======', data: ['0','0','0','0','0','0','0','0']},
  {name: 'ATMCHSEL',  wave: '0345345..', data: ['CH0', 'CH1', 'CH2', 'CH0', 'CH1', 'CH2']},
  {name: 'ATMCHSEL_DATA', wave: '0.34534..', data: ['CH0', 'CH1', 'CH2', 'CH0', 'CH1']},
  {name: 'LASTWORD',  wave: '0...1.1..'}
]}
```

### Key Timing Points:
*   **ATMCHSEL**: Updates at the rising edge of the cycle where the conversion *starts*.
*   **ATMCHSEL_DATA**: Appears 1 cycle later, perfectly aligned with when the ADC would assert `ADC_DONE` and valid data.

---

## Configuration Registers

The module behavior is controlled by the following inputs (conceptually registers from the config block):

| Signal | Width | Description |
| :--- | :--- | :--- |
| `ENSAMP_sync` | 1 | **Enable Sampling**. Master switch for the sequencer. |
| `CHEN_sync` | 8 | **Channel Enable Mask**. Bit N enables Channel N. The sequencer skips disabled channels. |
| `OSR_sync` | 4 | **Oversampling Ratio**. Defines the conversion length.<br>• `0`: SAR Mode (1 cycle)<br>• `1-15`: NS Mode (`4*OSR + 2` cycles) |
| `ENLOWPWR_sync` | 1 | **Low Power Mode**. When set, forces the physical mux output `CHSEL` to follow `ATMCHSEL`. When clear, `CHSEL` is static? *(Note: Code `assign CHSEL = ENLOWPWR ? atmchsel : CHEN` implies static `CHEN` drive if not low power. This might be a legacy feature).* |

---

## Output Signals

| Signal | Description |
| :--- | :--- |
| `ATMCHSEL[7:0]` | The **Look-Ahead** mux selection. Connects to the analog mux hardware. Updates *before* data is ready. |
| `ATMCHSEL_DATA[7:0]` | The **Data-Aligned** mux ID. Connects to the FIFO to tag the *current* data word. |
| `LASTWORD` | **Frame Sycronization**. High when `ATMCHSEL_DATA` corresponds to the last enabled channel in the sequence. Used by FIFO to packetize data. |
