# analyze_tracebuf.py
# EP (C) 2019-11-02

import subprocess

# Read the binary dumpfile
# src = open("readback/status-blackice.bin", "rb")
src = open("readback/flea_status.bin", "rb")
data = src.read(4096)
src.close()
# print(data)

# Be ready to compare with system rom
romf=open("roms/994aROM.bin", "rb")
romdata = romf.read(8192)
romf.close()

# Bring up our disassmebler
disassembled = ""

# Ok now data is our 4096 byte array. The interesting data is the last 2K.
# First read the index byte and determine which was the last written entry+1.
index = data[2048+2]
# now let's just roll through the data and display it
for i in range(0,255):
    j = index+i+1
    if j > 255:
        j=j-256
    adr = (data[2048+j*8+6] << 8) + data[2048+j*8+7]
    dat = (data[2048+j*8+4] << 8) + data[2048+j*8+5]
    ctrl = data[2048+j*8+3]
    s = ""

    # if we have a read from ROM, compare the content to expected
    if (ctrl & 1) and adr < 8192 and (adr & 1) == 0:
        romword = (romdata[adr]<<8) + romdata[adr+1]
        if romword != dat:
            print("mismatch {:04X} {:04X}".format(romword,dat))


    if(ctrl & 8):
        s += "IAQ "
        # dis = subprocess.Popen("../dis_mac", stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True, bufsize=0)
        dis = subprocess.Popen("../dis", stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True, bufsize=0)
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
    print("{} {:04X} {:04X} {}".format(s, adr, dat, disassembled))
