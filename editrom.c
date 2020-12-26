// editrom.c
// EP 2020-12-23
// Edit the TI-99/4A ROM to contain new wonderful instructions
// to speed up processing of GPL.

#include <stdio.h>
#include <string.h> // memcpy

void modify(unsigned char *addr, int offset, unsigned short w) {
    addr[offset] = w >> 8;
    addr[offset+1] = w & 0xFF;
}

int main(int argc,char *argv[]) {
    if(argc < 3) {
        fprintf(stderr, "Usage: editrom sourcerom.bin destrom.bin\n");
        return 2;
    }
    FILE *src = fopen(argv[1], "rb");
    if(!src) {
        fprintf(stderr, "Unable to open source file: %s\n", argv[1]);
        return 3;
    }

    unsigned char rom[8192];
    if(fread(rom, 1, 8192, src) != 8192) {
        fprintf(stderr, "Unable to read ROM\n");
        fclose(src);
        return 4;
    }
    fclose(src); src=NULL;

    // Modify ROM.
    modify(rom, 0x77a  , 0x0381);  // Insert custom instruction. GPLS
    modify(rom, 0x77a+2, 0x045B); // B *R11

    // Patch 0x07A8 routine with new MOVU instruction.
    // Note that the code jumps into this routine from multiple places, also to address 0x07AA.
    // So copy part of the original routine from 0x7A8 to 0x1346 (cassette write) and
    // patch BL @>07AA instruction at 0x00AA to call 0x1346 instead.
    memcpy(rom+0x1346, rom+0x7AA, 0x7BA-0x7AA);
    modify(rom, 0x00AC, 0x1346);
    // Now we can insert our custom instruction.
    modify(rom, 0x7A8,   0x389);        // Insert MOVU *R1,R0
    modify(rom, 0x7A8+2, 0x045B);       // B *R11
    // Fill in a section of memory with NOPs
    // for(int i=0x7A8+4; i<0x7BA; i += 2)
    //   modify(rom, i, 0x1000);       // NOP

    FILE *dst = fopen(argv[2], "wb");
    if(!dst) {
        fprintf(stderr, "Unable to open dest file: %s\n", argv[2]);
        return 3;
    }
    int t = fwrite(rom, 1, 8192, dst);
    if(t != 8192) {
        fprintf(stderr, "Dst write failed, fwrite returned %d\n", t);
        fclose(dst);
    }
    fclose(dst);
    return 0;
}