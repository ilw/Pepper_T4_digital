# Pepper T4


```{toctree}
:hidden:

units/README.md
units/PRESTUDY.md

```

This is the circuit design reference for the Pepper-T4 chip designed with the
TSMC 180 nm BCD2 technology.

## Overview

Pepper is a multi-channel bipolar or monopolar electrophysiology chip primarily 
targeted at implanted neural sensing, with an architecture designed to support 
parallel operation of multiple chips to scale the total channel count of a system. 

The chip is designed for connection to macroelectrodes (Typically >1mm2 surface 
area) implanted in, or in the vicinity of, neural tissue. The chip will amplify 
and digitise low frequency electrical signals picked up by these electrodes 
such as local field potentials (LFPs) or electroencephalography (EEG) signals. 
The Pepper chip can be configured and data read out through the digital output 
over a standard Serial Peripheral Interface (SPI) link, where the chip acts as 
an SPI peripheral. 


## System Targets

| ID    | Requirement                                                                                                                           |
|:------|:--------------------------------------------------------------------------------------------------------------------------------------|
| DI-1  | The chip power consumption must be less than 500uW                                                                                    |
| DI-2  | The chip must have at least 16 channels                                                                                               |
| DI-3  | Gain variation due to drift and expected operating temperature must be less than 10% of nominal.                                      |
| DI-4  | Maximum tolerated differential input range must be greater than 20mV                                                                  |
| DI-5  | Input referred noise must be less than 6uV pk-trough (0.5-50Hz bandwidth)                                                             |
| DI-6  | Gain flatness within +0.8dB and -3dB across the bandwith of 0.5-50Hz                                                                  |
| DI-7  | Common mode rejection at powerline frequency (50-60Hz) of 80dB in the presence of +/- 150mV DC shift.                                 |
| DI-8  | High pass filter cutoff must be <0.2Hz                                                                                                |
| DI-9  | Low pass cutoff must be be >250Hz                                                                                                     |
| DI-10 | Sampling rate must be greater than twice the low pass cutoff (>500Hz)                                                                 |
| DI-11 | Sampling rate must be a power of 2 in Hz                                                                                              |
| DI-12 | Resolution must be smaller than 3uV                                                                                                   |
| DI-13 | Data must be streamed out over SPI                                                                                                    |
| DI-14 | The device should indicate if an amplification stage goes into saturation                                                             |
| DI-15 | The device should indicate when lead wires become disconnected                                                                        |
| DI-16 | The chip must record all channels against known reference(s)                                                                          |
| DI-17 | Input impedance must be greater than 3MOhms at 1kHz                                                                                   |
| DI-18 | The gain at the chip must change less than ¬±10% in the presence of a ¬±150 mV DC shift                                               |
| DI-19 | in a single fault condition, the chip must not output a voltage at any electrode of more than 1.8v relative to lowest voltage on chip |
| DI-20 | The DREAM_Trial Device weight should be no higher than 750 grams, excluding connectors and cables                                     |
| DI-21 | The device maximum dimensions of the DREAM_Trial Device, excluding cabling, should be no more than 15 x 20 x 5 cm                     |
| DI-22 | Use of the DREAM_Trial device should leave the patient's arms and hands free during use                                               |
| DI-23 | The Device needs to be powered by a battery                                                                                           |



