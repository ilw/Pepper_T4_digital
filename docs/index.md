# Pepper_T4 Digital Documentation

This is the technical documentation for the **Pepper_T4 Digital Logic**, a mixed-signal controller system designed to interface an external host via SPI with an 8 channel Analog Front End (AFE) and ADC.

## What is Pepper_T4?

Pepper_T4 digital manages configuration, timing generation, and high-speed data buffering across two primary clock domains:
- **SCK Domain**: SPI clock domain for command interpretation and register access
- **HF_CLK Domain**: High-frequency system clock for ADC, AFE control, and status monitoring

## Documentation Sections

### [System Overview](system_overview.md)
High-level theory of operation, data flow architecture, and key system constraints. Start here to understand how the system functions as an SPI slave and the interaction between major blocks.

- [Block Diagram](system_overview/block_diagram.md) - Top-level module interconnections and IO ports

### [Core Blocks](core_blocks/command_interpreter.md)
Detailed documentation for the critical building blocks:

- [Command Interpreter](core_blocks/command_interpreter.md) - Main FSM controlling SPI commands and register access
- [FIFO](core_blocks/fifo.md) - Asynchronous dual-clock FIFO for ADC data buffering
- [CDC Sync](core_blocks/cdc_sync.md) - Clock domain crossing synchronizers

### [Functional Logic](functional/status_logic.md)
Status monitoring, error handling (overflow, underflow, saturation), and reset architecture.

### [Peripherals](peripherals/atm_control.md)
Register maps and peripheral control logic:

- [ATM Control](peripherals/atm_control.md) - Analog Test Mux controller
- [Configuration Registers](peripherals/configuration_registers.md) - Complete register map and bit field definitions
- [Temperature Sensor](peripherals/temp_sense.md) - On-chip temperature sensor control

## Building the Documentation

To view this documentation locally with live reload:

```bash
mkdocs serve
```

Then navigate to `http://127.0.0.1:8000` in your browser.

To build a static site:

```bash
mkdocs build
```

The static files will be generated in the `site/` directory.

---

!!! tip "Navigation Tips"
    Use the tabs above to browse by section, or use the search bar (top right) to find specific modules or topics.
