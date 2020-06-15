# icy99
TI-99/4A FPGA implementation for the Icestorm toolchain.

Initial commit 2020-06-15. I will add documentation once I have a bit more time.

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

 
 
