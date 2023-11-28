
import os, gc, ecp5, machine
os.mount(machine.SDCard(slot=3),"/sd")

# the following are not supposed to be in root directory
a = ['ti994a_ulx3s.bit', 'VDP9938.bin', '994aROM.Bin']
for i in a:
    os.remove(i)

    