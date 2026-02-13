# System Overview

## Introduction
**Pepper T4 digital logic** is a mixed-signal controller system designed to interface an external host (via SPI) with an 8 channel Analog Front End (AFE) and ADC. It manages configuration, timing generation (`SAMPLE_CLK`), and high-speed data buffering.

The digital core operates on two primary clock domains:
*   **SCK Domain**: The SPI clock domain, used for command interpretation and register access.
*   **HF_CLK Domain**: The high-frequency system clock, used for the ADC, AFE control, and status monitoring.

## Theory of Operation
The system functions as an SPI Slave. The data flow is as follows:

1.  **Command Phase**: The Host sends a command byte via SPI.
    *   The `spiCore` deserializes this into `cmd_byte`.
    *   The `Command_Interpreter` parses the opcode (Read Reg, Write Reg, Read Data).
2.  **Execution Phase**:
    *   **Register Write**: Data is written to `Configuration_Registers`. If the target is in the `HF_CLK` domain, it is synchronized via `CDC_sync`.
    *   **Register Read**: Data is retrieved from `Configuration_Registers` or `Status_Monitor` and loaded into the `tx_buff` for transmission.
    *   **Data Read**: ADC samples are popped from the `FIFO` and streamed to the host.

## polling vs Interrupts
The system provides 2 hardware interrupt pins (`DATA_RDY` and `INT`). `DATA_RDY` asserts when the internal FIFO has a number of frames of data available to read. `INT` asserts when any error flag (Overflow, Underflow, Saturation) is set. Alternatively, the Host can poll the Status Register (returned as the first byte of every transaction) to monitor system health.

## Key Limitations & Constraints

!!! warning "Write Protection during Sampling"
    To prevent glitches and meta-stability issues, **Configuration Register writes are BLOCKED when Sampling is Active (`ENSAMP=1`)**.

    Attempts to write to registers 0x00-0x22 will be ignored by the hardware while `ENSAMP` is high, with the following **exceptions** (Safe Registers):
    *   **0x12**: `AFERSTCH` (Allows resetting channels dynamically).
    *   **0x13**: Buffer/LNA control (Safe for dynamic updates).
    *   **0x23**: Contains `ENSAMP` itself (allows disabling sampling).

    **Procedure to change configuration:**
    1.  Write `0x00` to Register `0x23` (Disable Sampling).
    2.  Poll Status to confirm `ENSAMP` flag is low.
    3.  Perform configuration writes.
    4.  Write `0x80` to Register `0x23` (Enable Sampling).

!!! warning "Procedural Limitation: FIFO Readout Boundary"
    **After writing `ENSAMP=0` (Disable Sampling), the MCU MUST end the current SPI transaction (raise CS) before issuing any `RDDATA` commands.**

    If you attempt to read from the FIFO immediately after writing `ENSAMP=0` within the same transaction, the data returned is undefined. The disable-to-read sequence requires a transaction boundary to reset internal pointers correctly.

## Internal Block Summary

| Module | Description |
| :--- | :--- |
| **spiCore** | Physical layer interface for 4-wire SPI (Mode 0). |
| **Command_Interpreter** | Main FSM. Parses SPI commands, controls FIFO readout, and manages Register/Status access. |
| **Configuration_Registers** | Stores the 512-bit configuration state. Maps SPI registration addresses to physical control signals. |
| **CDC_sync** | Clock Domain Crossing. Safe transfer of control signals (SCK -> HF_CLK) and status flags (HF_CLK -> SCK). |
| **Dual_phase_gated_burst_divider** | Generates the precise `SAMPLE_CLK` from `HF_CLK` based on configured dividers. |
| **FIFO** | Asynchronous FIFO buffering ADC data (HF_CLK domain) for SPI readout (SCK domain). |
| **Status_Monitor** | Aggregates error flags (Overflow, Saturation) and system state into a unified status register. |
| **ATM_Control** | Analog Test Mux controller. Sequences channel selection signals aligned with ADC conversion windows. |
| **TempSense** | Controls the on-chip temperature sensor and its specialized readout sequence. |
