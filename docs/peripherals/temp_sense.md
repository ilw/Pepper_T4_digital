# Temperature Sensor Control

The Temperature Sensor Control peripheral manages the operation of the on-chip temperature sensor. It operates in a **one-shot** mode, triggering a single measurement sequence for each assertion of the enable signal. The peripheral consists of two main blocks: `TempSense_Control` for timing/control logic and `Temperature_Buffer` for data storage.

## Functional Description

The `TempSense_Control` module is responsible for generating the `temp_run` signal, which enables the `SAMPLE_CLK` and the ADC/Sensor logic.

### One-Shot Operation
1.  **Arming**: The logic monitors the `ENMONTSENSE_sync` signal (synchronized to `HF_CLK`). A **rising edge** on `ENMONTSENSE_sync` arms the controller and asserts `temp_run` high.
2.  **Running**: While `temp_run` is high, the sensor performs its conversion.
3.  **Completion**: The controller waits for the `DONE` signal from the sensor. Upon receiving `DONE`, `temp_run` is immediately de-asserted (set to low).
4.  **Re-Arming**: The controller enters an idle state. To trigger a new measurement, `ENMONTSENSE_sync` must first be de-asserted (low) and then asserted (high) again.

This "one-shot" behavior ensures that power is consumed only during the requested measurement interval, even if the enable signal remains high.

## Buffer Logic

The `Temperature_Buffer` module captures and holds the valid temperature result.

1.  **Arming**: Similar to the control logic, the buffer arms itself on the rising edge of `ENMONTSENSE_sync`.
2.  **Capture**: When the `DONE` signal is asserted, if the buffer is armed, it captures the 16-bit `RESULT` from the sensor into an internal register.
3.  **Storage**: The `TEMPVAL` output continuously drives this stored value until the next valid measurement completes.
4.  **Safety**: The buffer logic includes an interlock (flagged as `armed`) to ensure it only updates once per enable cycle, preventing spurious updates or data corruption if `DONE` were to glitch or re-assert unexpectedly without a new enable request.

## IO Listing

### TempSense_Control

| Signal Name | Direction | description |
| :--- | :--- | :--- |
| `HF_CLK` | Input | High-frequency system clock. |
| `NRST_sync` | Input | Active-low reset (synchronized). |
| `ENMONTSENSE_sync` | Input | Control signal to enable temperature sensing (Level sensitive, rising edge triggers one-shot). |
| `DONE` | Input | Signal from sensor indicating conversion is complete. |
| `temp_run` | Output | Active-high enable for the sensor/ADC. |

### Temperature_Buffer

| Signal Name | Direction | Description |
| :--- | :--- | :--- |
| `ENMONTSENSE_sync` | Input | Control signal used to arm the capture logic. |
| `DONE` | Input | Strobe indicating valid data is ready to be captured. |
| `NRST_sync` | Input | Active-low reset. |
| `SAMPLE_CLK` | Input | Clock for the buffer registers (typically slower than HF_CLK). |
| `RESULT` | Input | 16-bit temperature data from the sensor. |
| `TEMPVAL` | Output | 16-bit register output holding the last valid temperature reading. |
