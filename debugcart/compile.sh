# Compile.sh
# EP 2020-10-18

xas99.py -L vdpload.lst -R -c vdpload.asm
unzip -o vdpload.rpk
./pad vdpload.bin vdpload0.bin 4096
# Break VDPDUMP.BIN to five parts 4k+4k+4k+4k+1k
dd if=VDPDUMP.BIN of=dump0.bin bs=1 count=4096
dd if=VDPDUMP.BIN of=dump1.bin bs=1 count=4096 skip=4096
dd if=VDPDUMP.BIN of=dump2.bin bs=1 count=4096 skip=8192
dd if=VDPDUMP.BIN of=dump3.bin bs=1 count=4096 skip=12288
dd if=VDPDUMP.BIN of=dump4_.bin bs=1 count=8 skip=16384
./pad dump4_.bin dump4.bin 4096
# Build the cart image
cat vdpload0.bin dump0.bin \
    vdpload0.bin dump1.bin \
    vdpload0.bin dump2.bin \
    vdpload0.bin dump3.bin \
    vdpload0.bin dump4.bin \
    vdpload0.bin dump0.bin \
    vdpload0.bin dump0.bin \
    vdpload0.bin dump0.bin \
    > dumploac.bin
echo "Generated dumploac.bin"

