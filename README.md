# icy99
TI-99/4A FPGA implementation for the Icestorm toolchain.

Initial commit 2020-06-15. I will add documentation once I have a bit more time. The software stucture is a bit of a mess. I am moving the files into this github repository from my own repository, please let me know if some files are missing.

The system here is a verilog port from my existing EP994A VHDL version of the TI-99/4A. The main difference between this version is that a unified memory architecture (UMA) model is supported, allowing this core to run even on the Blackice-II board, with the modest ICE40HX4K FPGA. This FPGA does not have enough block RAM to support the video system memory on-chip. Thus, thanks to UMA, the external 256K x 16bit memory is used for both CPU RAM, ROM, GROM and VDP RAM memories.

The archictecture runs at 25MHz, the performance is around 7x of the original TI-99/4A. My initial goal with the EP994 was to build a very fast TI-99/4A implementation. Due to this the core has never been cycle accurate. I may accurate this later.

The repository does not include ROM files. The necessary ROM files are:
* 994AGROM.Bin system GROM file
* 994aROM.Bin system ROM 

create-mem-from-bin.py is a Python 3 program which will generate Verilog memory initialization files from binary files.

The design targets the following FPGA boards:
| Board       | top module      | make target |
|-------------|-----------------|-------------|
| ULX3S       | top_ulx3s.v     | ti994a_ulx3s.bit |
| Blackice-II | top_blackice2.v | next9900.bin |
| Flea Ohm    | top_flea.v      | flea_ohm.bit |

 Thus, for example to build the version for flea_ohm board:

 make flea_ohm.bit
 
 The ULX3S and Flea Ohm versions of this system embed the TI-99/4A ROMS as FGPA block RAMs. For the BlackIce-II board this is not possible, as the internal block RAM capacity is too small. For that system (and also the others) the ROMs can be initilized with the MEMLOADER program. This is a Windows program enabling the memories to be initialized over a serial port. I believe I have documented some of this in the EP994A. I will add the memloader source code to this repository later as well.
 
I have used a mixed computer setup for development: a windows box running Windows Subsystem for Linux as the main development environment to run Icestorm (yosys, nextpnr), a Mac for some of the development with the same toolchain. Windows is required currently to run MEMLOADER.
