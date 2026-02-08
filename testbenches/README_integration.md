# Integration Testbench Usage Guide

## Overview

The integration testbench provides end-to-end verification of the Pepper T4 digital system, including:
- SPI communication
- ADC data acquisition
- Multiplexer control
- FIFO operation
- Sampling enable/disable flow

## Files Created

### Testbench Components
1. **`dummy_ADC.v`** - ADC model with CSV data loading
2. **`dummy_Mux.v`** - Analog multiplexer model
3. **`spi_master_bfm.v`** - SPI master bus functional model
4. **`tb_top_level_integration.v`** - Main integration testbench
5. **`adc_data.csv`** - Sample data file (16 samples × 8 channels)

## CSV Data Format

The ADC loads data from `adc_data.csv` with format:
```
ch0,ch1,ch2,ch3,ch4,ch5,ch6,ch7
1000,1100,1200,1300,1400,1500,1600,1700
2000,2100,2200,2300,2400,2500,2600,2700
...
```

- Each row = one sample across all 8 channels
- Values are decimal (will be converted to 16-bit)
- Up to 1024 samples supported

## Customizing Test Data

To use your own data:

1. **Create CSV file** with same format
2. **Modify testbench** to point to your file:
   ```verilog
   dummy_ADC #(
       .DATA_FILE("your_data.csv"),
       .CONVERSION_CYCLES(5)
   ) adc ( ... );
   ```

## Running the Testbench

### ModelSim/QuestaSim
```bash
# Compile all source files
vlog source/*.v testbenches/*.v

# Run integration test
vsim -c tb_top_level_integration -do "run -all; quit"
```

### Icarus Verilog
```bash
iverilog -o sim source/*.v testbenches/*.v
vvp sim
```

## Test Sequence

The testbench performs these tests automatically:

1. **SPI Register Write** - Configures CHEN, PHASE1DIV1
2. **Enable Sampling** - Starts ADC conversions
3. **Mux Control** - Verifies channel switching
4. **FIFO Readout** - Reads data via SPI
5. **Disable Sampling** - Stops conversions
6. **Stale Data Check** - Re-enables and verifies fresh data
7. **Register Readback** - Verifies configuration

## Expected Output

```
========================================
Top-Level Integration Test Starting
========================================

=== Test 1: SPI Register Write ===
Wrote CHEN=0x07 via SPI
...

=== Test 4: FIFO Readout via SPI ===
Sent RDDATA command, Status response: 0x...
  Word 0: 0x03E8  (1000 decimal from CSV)
  Word 1: 0x044C  (1100 decimal from CSV)
  ...

========================================
Integration Test Complete
========================================
```

## Troubleshooting

### "Could not open adc_data.csv"
- Ensure CSV file is in simulator working directory
- Check file permissions
- Testbench will use default incrementing pattern if file not found

### No ADC conversions detected
- Check `ENSAMP` is being set via SPI
- Verify clock is running
- Check `ATMCHSEL` is switching channels

### FIFO reads all zeros
- Verify ADC data is being written
- Check `DATA_RDY` flag
- Ensure sufficient time for samples to accumulate

## Modifying the Test

### Change enabled channels
```verilog
spi.send_word(16'h90FF, spi_rx_data);  // Enable all 8 channels
```

### Adjust sampling rate
```verilog
spi.send_word(16'h8508, spi_rx_data);  // PHASE1DIV1 = 8 (slower)
```

### Read multiple FIFO frames
```verilog
for (j = 0; j < 4; j = j + 1) begin  // Read 4 frames
    spi.send_word(16'hC000, spi_rx_data);
    for (i = 0; i < 8; i = i + 1) begin
        spi.read_word(spi_rx_data);
    end
end
```
