rm tms9918_tb
iverilog -Wall -o tms9918_tb tms9918_tb.v tms9918.v vga_sync.v dualport_par.v
./tms9918_tb -lxt2

