#!/usr/local/bin/python3
# explain_vdp.py
# Erik Piehl (C) 2020
# decode VDP register values to display what is going on


def explain(r, names):
    s = ""
    for i in range(0,8):
       if r & (1 << (7-i)):
           s = s+" "+names[i]
    return s
    

def show_mode(regs):
    addr2 = (regs[2] & 0xF) << 10   # (4 bits) 1K boundaries
    addr3 = regs[3] << 6            # (8 bits) color table 64 byte boundaries 
    addr4 = (regs[4] & 7) << 11     # (3 bits) pattern generator 2K boundaries
    addr5 = (regs[5] & 0x7F) << 7   # (7 bits) sprite attribute table 128 byte boundaries
    addr6 = (regs[6] & 7) << 11     # (3 bits) sprite pattern generator 2K boundaries

    s0 = explain(regs[0], [ "", "", "", "", "", "", "Bitmap", "Ext_vid"])
    s1 = explain(regs[1], [ "16K", "/Blank", "Int_on", "Text", "Multicolor", "", "16x16", "2x2"])
    print("R0 {:02X} {}".format(regs[0], s0), end='')
    print("R1 {:02X} {}".format(regs[1], s1))
    m3 = regs[0] & 2
    m1 = regs[1] & 0x10
    m2 = regs[1] & 0x08 # Text mode
    m4 = regs[0] & 4    # 80 column mode
    if (not m1 and not m2 and not m3):
        modes="Graphics 1 mode"
    elif (not m1 and not m2 and m3):
        # in grahics mode 2 only the top bit of character and color table matter.
        modes="Graphics 2 mode"
        addr4 = addr4 & 0x2000
        addr3 = addr3 & 0x2000
    elif (not m1 and m2 and m3):
        modes="Multicolor mode"
    elif (m1 and not m2 and not m3 and not m4):
        modes="40 column text mode"
    elif (m1 and not m2 and not m3 and m4):
        modes="80 column text mode"
    else:
        modes="Non-standard video mode"
    print("m1={} m2={} m3={} m4={}: {}".format(m1,m2,m3, m4, modes))


    print("Image table at         {:04X} R2, character numbers.".format(addr2))
    print("Color table at         {:04X} R3 (not used in text mode, multicolor mode)".format(addr3))
    print("Character table at     {:04X} R4, character table, i.e. fonts".format(addr4))
    print("Sprite attribute table {:04X} R5, 4 bytes per sprite".format(addr5))
    print("Sprite pattern table   {:04X} R6, 4 bytes per sprite".format(addr6))
    print("Foreground color      {:2X} R7 high nibble".format(regs[7] >> 4))
    print("Background color      {:2X} R7 low nibble".format(regs[7] & 0xF))

def explain_regs(name, regs):
    print("-------------")
    print(name)
    print("-------------")
    show_mode(regs)

#Main, go through some games
explain_regs("Menu",     [0x00, 0xE0, 0xF0, 0x0E, 0xF9, 0x86, 0xF8, 0xF7 ])
explain_regs("Invaders", [0x00, 0xE2, 0xF0, 0x0E, 0xF9, 0x86, 0xF8, 0xF1 ])
explain_regs("Parsec",   [0x02, 0xE2, 0x06, 0xFF, 0x03, 0x36, 0x03, 0x11 ])
explain_regs("Defender", [0x00, 0xE2, 0x00, 0x0E, 0x01, 0x3E, 0x02, 0x01])
explain_regs("TurboForth", [0x00, 0xf0, 0x00, 0x0e, 0x01, 0x06, 0x00,0xf4])