# Configuration Registers

The `Configuration_Registers` module implements a bank of 36 8-bit registers, providing a total of 288 bits of configuration data to various blocks in the Pepper T4 digital system. These registers are primarily written via the SPI interface during the configuration phase.

## Overview

- **Address Range**: `0x00` to `0x23` (36 registers).
- **Reset State**: All registers are reset to `0x00` when `NRST` is asserted (active low).
- **Write Mechanism**: Writes occur on the rising edge of `SCK` when `wr_en` is high and the address is within the valid range (< 36).
- **Output**: The concatenated 512-bit `cfg_data` bus provides register values to the system. Bits `[287:0]` contain the register data, while `[511:288]` are tied low.

## Register Map

| Address | Register Name | Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | CREF Control | R/W | `0x00` | Voltage regulator controls (AFE, ADC, DIG). |
| `0x01` | CREF Trim 1 | R/W | `0x00` | Resistor trimming for Bandgap and AFE regulators. |
| `0x02` | CREF Trim 2 | R/W | `0x00` | Resistor trimming for ADC and DIG regulators. |
| `0x03` | SPARECREF | R/W | `0x00` | Spare 8-bit register for CREF. |
| `0x04` | BIAS Control | R/W | `0x00` | Bias section, Temp sensor, and ITEST enablement. |
| `0x05` | BIAS Trim / LNA0 | R/W | `0x00` | Bias trim and CH0 AFELNA current settings. |
| `0x06` | LNA 1/2 Trim | R/W | `0x00` | CH1 and CH2 AFELNA current settings. |
| `0x07` | LNA 3/4 Trim | R/W | `0x00` | CH3 and CH4 AFELNA current settings. |
| `0x08` | LNA 5/6 Trim | R/W | `0x00` | CH5 and CH6 AFELNA current settings. |
| `0x09` | LNA 7 / LPF 0 Trim | R/W | `0x00` | CH7 LNA and CH0 LPF current settings. |
| `0x0A` | LPF 1/2 Trim | R/W | `0x00` | CH1 and CH2 AFELPF current settings. |
| `0x0B` | LPF 3/4 Trim | R/W | `0x00` | CH3 and CH4 AFELPF current settings. |
| `0x0C` | LPF 5/6 Trim | R/W | `0x00` | CH5 and CH6 AFELPF current settings. |
| `0x0D` | LPF 7 / BUF Trim | R/W | `0x00` | CH7 LPF and AFEBUF current settings. |
| `0x0E` | ADC Trim | R/W | `0x00` | IT setting for ADC. |
| `0x0F` | SPAREBIAS1 | R/W | `0x00` | Spare 8-bit register for BIAS. |
| `0x10` | SPAREBIAS2 | R/W | `0x00` | Spare 8-bit register for BIAS. |
| `0x11` | AFE Control 1 | R/W | `0x00` | Enablement for LNA, LPF, BUF, and Sensing/Ref modes. |
| `0x12` | AFE Reset | R/W | `0x00` | Reset (active high) for selected AFE channels. |
| `0x13` | AFE Control 2 | R/W | `0x00` | AFEBUF reset, gain, and monitoring controls. |
| `0x14` | LPF Bandwidth | R/W | `0x00` | AFELPF cut-off frequency tuning. |
| `0x15` | Low Power Mode | R/W | `0x00` | Enable sequential channel switching. |
| `0x16` | Channel Enable | R/W | `0x00` | Selection of channels to be sampled. |
| `0x17` | SPAREAFE | R/W | `0x00` | Spare 8-bit register for AFE. |
| `0x18` | ATM Control 1 | R/W | `0x00` | Analog Test Mux Enablement (IN/OUT/LNA/LPF/BUF). |
| `0x19` | ATM mode | R/W | `0x00` | Operation mode of the ATM. |
| `0x1A` | SPAREATM | R/W | `0x00` | Spare 8-bit register for ATM. |
| `0x1B` | ADC Control 1 | R/W | `0x00` | ADC Over-sampling ratio, DWA, Chopper, and Error Shaping. |
| `0x1C` | ADC Control 2 | R/W | `0x00` | ADC Gain, Ext Clock, and Override controls. |
| `0x1D` | ADC / Test Control | R/W | `0x00` | Digital/Analog test signal selection. |
| `0x1E` | SPAREADC1 | R/W | `0x00` | Spare 8-bit register for ADC. |
| `0x1F` | SPAREADC2 | R/W | `0x00` | Spare 8-bit register for ADC. |
| `0x20` | Digital Phase 1 Div | R/W | `0x00` | Phase divider settings for digital control. |
| `0x21` | Digital Phase 1 Cnt | R/W | `0x00` | Phase count and secondary divider settings. |
| `0x22` | Digital Phase 2 Cnt | R/W | `0x00` | Phase 2 count settings. |
| `0x23` | Global Control | R/W | `0x00` | Sample Enable, Force Write, and FIFO Watermarks. |

---

## Bit Fields

### `0x00` - CREF Control
| Bit | Name | Default | Description |
| :--- | :--- | :--- | :--- |
| `0` | `ENREGAFE` | `0` | Enable AFE Voltage Regulator. |
| `1` | `ENREGADC` | `0` | Enable ADC Voltage Regulator. |
| `2` | `PDREGDIG` | `0` | Power down DIG Voltage Regulator (0=ON, 1=OFF). |
| `7:3` | `RESERVED` | `0` | |

### `0x11` - AFE Control 1
| Bit | Name | Default | Description |
| :--- | :--- | :--- | :--- |
| `0` | `ENAFELNA` | `0` | Enable AFELNA. |
| `1` | `ENAFELPF` | `0` | Enable AFELPF. |
| `2` | `ENAFEBUF` | `0` | Enable AFEBUF. |
| `3` | `SENSEMODE` | `0` | Sensing mode: 0 = Monopolar, 1 = Bipolar. |
| `4` | `ENREFBUF` | `0` | Enable external REF buffer (0 = Bypass). |
| `5` | `REFMODE` | `0` | Electrode reference: 0 = External, 1 = Internal. |
| `6` | `AFELPFBYP` | `0` | Bypass LPF (LNA direct to BUF). |
| `7` | `RESERVED` | `0` | |

### `0x13` - AFE Control 2
| Bit | Name | Default | Description |
| :--- | :--- | :--- | :--- |
| `0` | `AFEBUFRST` | `0` | Reset AFEBUF (Active High). |
| `2:1` | `AFEBUFGT<1:0>` | `00` | Set AFEBUF gain. |
| `3` | `ENMONTSENSE` | `0` | Enable Monitoring Temperature Sensor. |
| `4` | `ENLNAOUT` | `0` | Enable LNA outputs to ATM (bypass AFEBUF). |
| `5` | `ENLPFOUT` | `0` | Enable LPF outputs to ATM (bypass AFEBUF). |
| `6` | `ENMONAFE` | `0` | Enable AFE section monitoring. |
| `7` | `RESERVED` | `0` | |

### `0x1B` - ADC Control 1
| Bit | Name | Default | Description |
| :--- | :--- | :--- | :--- |
| `0` | `ENADCANALOG` | `0` | Enable ADC analog section. |
| `1` | `ENMES` | `0` | Mismatch Error Shaping Enable. |
| `2` | `ENCHP` | `0` | Chopper Enable. |
| `3` | `ENDWA` | `0` | Dynamic Weighted Average Enable. |
| `7:4` | `ADCOSR<3:0>` | `0000` | ADC Over-Sampling Ratio. |

### `0x23` - Global Control
| Bit | Name | Default | Description |
| :--- | :--- | :--- | :--- |
| `0` | `PHASE2COUNT2[8]`? | `0` | LSB bits of Phase 2 Count (from CSV logic). |
| `1` | `PHASE2COUNT2[9]`? | `0` | MSB bits of Phase 2 Count. |
| `5:2` | `FIFOWATERMARK` | `0` | Data frames before `DATAREADY` triggers. |
| `6` | `FORCEWREN` | `0` | Enable register writes during sampling (not recommended). |
| `7` | `ENSAMP` | `0` | **GLOBAL ENABLE** - Starts sampling process. |

> [!NOTE]
> `PHASE2COUNT2` bits at address `0x23` represent the most significant bits of the Phase 2 count, extending the 8-bit value in `0x22`.
