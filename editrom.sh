# editrom.sh
gcc tools/editrom.c -o editrom
./editrom roms/994aROM.Bin roms/99opt.bin
hexdump -C roms/994aRom.Bin > roms/original.txt
hexdump -C roms/99opt.bin > roms/optimized.txt
fmdiff roms/original.txt roms/optimized.txt
