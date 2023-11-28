# analyze-rom.py
#
# EP 2020-12-16 find certain instruction sequences in ROM.


import subprocess

def disassemble(dat):
        dis = subprocess.Popen("./dis_mac", stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True, bufsize=0)
        # dis = subprocess.Popen("../dis", stdin=subprocess.PIPE, stdout=subprocess.PIPE, universal_newlines=True, bufsize=0)
        dis.stdin.write("{:04X}\n".format(dat))  
        k = dis.communicate()
        disassembled = k[0]
        dis.wait(100)
        disassembled = disassembled[:-1]
        return disassembled

def find_word(romwords, term):
    addresses = []
    for i in range(0, len(romwords)-len(term)):
        match = True
        for j in range(0, len(term)):
            if romwords[i+j] != term[j]:
                match = False
        if match:
            addresses.append(i)
    return addresses


# Be ready to compare with system rom
romf=open("../roms/994aROM.bin", "rb")
romdata = romf.read(8192)
romf.close()


# print(len(romdata))

# Modify ROM to 16 bit values
rom16 = []
word_count = int(len(romdata)/2-1)
print(word_count)
for i in range(0,word_count):
    print(i)
    rom16.append( (romdata[i*2] << 8) + romdata[i*2+1] )

# Bring up our disassembler
disassembled = ""
for k in range(0x70, 0x80, 2):
    print("{:04X} {:04X} {}".format(k, rom16[k >> 1], disassemble(rom16[k >> 1])))

print("Looking for 77A")
a = find_word(rom16, [0x77A])
[print(hex(k<<1)) for k in a]

print("Looking for BL 77A")
a = find_word(rom16, [0x06a0, 0x77A])
[print(hex(k<<1)) for k in a]

print("Looking for all BL @ADDR instructions")
a = find_word(rom16, [0x06a0])
[print(hex(k<<1)) for k in a]
print("Found {} instructions".format(len(a)))
