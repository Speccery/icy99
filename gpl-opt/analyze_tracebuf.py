# analyze_tracebuf.py
# EP (C) 2019-11-02
# EP updated 2023-11-28 with argparse

import subprocess
import argparse

parser = argparse.ArgumentParser(description="icy99 Tracebuffer Analyzer")
parser.add_argument("--src", type=str, help='Source tracebuffer file, 8k in size', default='gpl-opt/tb1.bin')
parser.add_argument("--rom", type=str, help='Path to TI ROM file for disassembly', default='roms/994aROM.bin')
parser.add_argument("--dis", type=str, help='Path to disassembler executable', default='./dis')
args = parser.parse_args()

# Read the binary dumpfile
# src = open("readback/status-blackice.bin", "rb")
try:
    src = open(args.src, "rb")
except FileNotFoundError:
    print(f"Source file {args.src} not found.")
    quit()
    
data = src.read(8192)
src.close()

# Be ready to compare with system rom
try:
    romf=open(args.rom, "rb")
except FileNotFoundError:
    print(f"Unable to open ROM file {args.rom}")
    quit()

romdata = romf.read(8192)
romf.close()

# Bring up our disassmebler
disassembled = ""

# Ok now data is our 8192 byte array. The interesting data is the last 4K.
# First read the index byte and determine which was the last written entry+1.
index = data[4096+2]
# now let's just roll through the data and display it
for i in range(0,255):
    j = index+i+1
    if j > 255:
        j=j-256
    adr = (data[4096+j*16+6] << 8) + data[4096+j*16+7]
    dat = (data[4096+j*16+4] << 8) + data[4096+j*16+5]
    ctrl = data[4096+j*16+3]
    # new tracebuf2 signals
    dat1 = (data[4096+j*16+14] << 8) + data[4096+j*16+15]
    dat2 = (data[4096+j*16+12] << 8) + data[4096+j*16+13]
    ctrl2 = data[4096+j*16+11]
    s = ""

    # if we have a read from ROM, compare the content to expected
    mismatch=""
    if (ctrl & 1) and adr < 8192 and (adr & 1) == 0:
        romword = (romdata[adr]<<8) + romdata[adr+1]
        if romword != dat:
            mismatch = "mismatch {:04X} {:04X}".format(romword,dat)


    if(ctrl & 8):
        s += "IAQ "
        dis = subprocess.Popen(args.dis, stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True, bufsize=0)
        dis.stdin.write("{:04X}\n".format(dat))  
        k = dis.communicate()
        disassembled = k[0]
        dis.wait(100)
        disassembled = disassembled[:-1]
    else:
        s += "    "
        disassembled = ""
    if(ctrl & 4):
        s += "INT "    # interrupt request active
    else:
        s += "    "

    if(ctrl & 2):
        s += "WR "
    else:
        s += "   "

    if(ctrl & 1):
        s += "RD "
    else:
        s += "   "

    if (i & 7) == 0:
        #           RD  0000 0000 X8 0024 0024  (mismatch 83E0 0000)
        print("               ADDR-DAT---X-DAT2-DAT1")

    # Add the additional fields after X
    tb2 = f"X{ctrl2:X} {dat2:04X} {dat1:04X} "

    if len(mismatch) > 0:
        print("{} {:04X} {:04X} {} ({}) {}".format(s, adr, dat, tb2, mismatch, disassembled))
    else:
        print(f"{s} {adr:04X} {dat:04X} {tb2} {disassembled}")
