// dis9900.c
// EP 2019-09-12
// Quick and dirty disassembler for TMS9900.
// This is a line by line disassembler designed to dissassemble from
// stdin to stdout, so that it can be used with gtkwave to analyze instructions.

#include <stdio.h>

enum ins9900 { dual_op_mult_mult, dual_op_mult_wr, xop, single_op,
    cru_multi_bit, cru_single_bit, jumps, shifts, immediates,
    internal_immediates, internal_store, rtwp };

#define INTLEN 32

struct instrucion_t {
    unsigned bin;
    unsigned mask;
    enum ins9900 type;
    char str[8];
} instructions[] = {
    // Dual operand instructions.
    // Dual operand with multiple addressing modes for source and destination
    { 0xA000, 0xF000, dual_op_mult_mult, "A" },
    { 0xB000, 0xF000, dual_op_mult_mult, "AB" },
    { 0x8000, 0xF000, dual_op_mult_mult, "C" },
    { 0x9000, 0xF000, dual_op_mult_mult, "CB" },
    { 0x6000, 0xF000, dual_op_mult_mult, "S" },
    { 0x7000, 0xF000, dual_op_mult_mult, "SB" },
    { 0xE000, 0xF000, dual_op_mult_mult, "SOC" },
    { 0xF000, 0xF000, dual_op_mult_mult, "SOCB" },
    { 0x4000, 0xF000, dual_op_mult_mult, "SZC" },
    { 0x5000, 0xF000, dual_op_mult_mult, "SZCB" },
    { 0xC000, 0xF000, dual_op_mult_mult, "MOV" },
    { 0xD000, 0xF000, dual_op_mult_mult, "MOVB" },
    // Dual operand with multiple addressing modes for source and workspace reg for dest
    { 0x2000, 0xFC00, dual_op_mult_wr, "COC" },
    { 0x2400, 0xFC00, dual_op_mult_wr, "CZC" },
    { 0x2800, 0xFC00, dual_op_mult_wr, "XOR" },
    { 0x3800, 0xFC00, dual_op_mult_wr, "MPY" },
    { 0x3C00, 0xFC00, dual_op_mult_wr, "DIV" },
    // XOP
    { 0x2C00, 0xFC00, xop, "XOP" },
    // Single operand instructions
    { 0x0440, 0xFFC0, single_op, "B" },
    { 0x0680, 0xFFC0, single_op, "BL" },
    { 0x040C, 0xFFC0, single_op, "BLWP" },
    { 0x04C0, 0xFFC0, single_op, "CLR" },
    { 0x0700, 0xFFC0, single_op, "SETO" },
    { 0x0540, 0xFFC0, single_op, "INV" },
    { 0x0500, 0xFFC0, single_op, "NEG" },
    { 0x0740, 0xFFC0, single_op, "ABS" },
    { 0x06C0, 0xFFC0, single_op, "SWPB" },
    { 0x0580, 0xFFC0, single_op, "INC" },
    { 0x05C0, 0xFFC0, single_op, "INCT" },
    { 0x0600, 0xFFC0, single_op, "DEC" },
    { 0x0640, 0xFFC0, single_op, "DECT" },
    { 0x0480, 0xFFC0, single_op, "X" },
    // CRU multibit
    { 0x3000, 0xFC00, cru_multi_bit, "LDCR" },
    { 0x3400, 0xFC00, cru_multi_bit, "STCR" },
    // CRU single bit
    { 0x1D00, 0xFF00, cru_single_bit, "SBO"},
    { 0x1E00, 0xFF00, cru_single_bit, "SBZ"},
    { 0x1F00, 0xFF00, cru_single_bit, "TB"},
    // jump instructions
    { 0x1300, 0xFF00, jumps, "JEQ" }, 
    { 0x1500, 0xFF00, jumps, "JGT" }, 
    { 0x1B00, 0xFF00, jumps, "JH" }, 
    { 0x1400, 0xFF00, jumps, "JHE" }, 
    { 0x1A00, 0xFF00, jumps, "JL" }, 
    { 0x1200, 0xFF00, jumps, "JLE" }, 
    { 0x1100, 0xFF00, jumps, "JLT" }, 
    { 0x1000, 0xFF00, jumps, "JMP" }, 
    { 0x1700, 0xFF00, jumps, "JNC" }, 
    { 0x1600, 0xFF00, jumps, "JNE" }, 
    { 0x1900, 0xFF00, jumps, "JNO" }, 
    { 0x1800, 0xFF00, jumps, "JOC" }, 
    { 0x1C00, 0xFF00, jumps, "JOP" }, 
    // shifts
    { 0x0A00, 0xFF00, shifts, "SLA" }, 
    { 0x0800, 0xFF00, shifts, "SRA" }, 
    { 0x0B00, 0xFF00, shifts, "SRC" }, 
    { 0x0900, 0xFF00, shifts, "SRL" }, 
    // immediate instructions, don't care N
    { 0x0220, 0xFFE0, immediates, "AI" },
    { 0x0240, 0xFFE0, immediates, "ANDI" },
    { 0x0280, 0xFFE0, immediates, "CI" },
    { 0x0200, 0xFFE0, immediates, "LI" },
    { 0x0260, 0xFFE0, immediates, "ORI" },
    // internal register load immediate
    { 0x02E0, 0xFFE0, internal_immediates, "LWPI"},
    { 0x0300, 0xFFE0, internal_immediates, "LIMI"},
    // internal register store
    { 0x02C0, 0xFFE0, internal_store, "STST"},
    { 0x02A0, 0xFFE0, internal_store, "STWP"},
    // RTWP and external instructions
    { 0x0380, 0xFFE0, rtwp, "RTWP" },
    { 0x0340, 0xFFE0, rtwp, "IDLE" },
    { 0x0360, 0xFFE0, rtwp, "RSET" },
    { 0x03C0, 0xFFE0, rtwp, "CKOF" },
    { 0x03A0, 0xFFE0, rtwp, "CKON" },
    { 0x03E0, 0xFFE0, rtwp, "LREX" },
    // end

    { 0,0, dual_op_mult_mult, "" }
};

char *addr_mode(char *s, unsigned mode, int *len) {
    *len = 0;
    switch((mode >> 4) &3) {
        case 0: sprintf(s, "R%d", mode & 0xF); break;
        case 1: sprintf(s, "*R%d", mode & 0xF); break;
        case 2: 
            if (mode & 0xF)
                sprintf(s, "@_R%d", mode & 0xF); 
            else
                sprintf(s, "@"); 
            *len = 1;
            break;
        case 3: sprintf(s, "*R%d+", mode & 0xF); break;
    }
    return s;
}

// state_in = 0: opcode
//          = 1: a parameter word
//          = 2: a paramater word followed by parameter word
// In other words, state_out is simply state_in -1 
int dasm_one(char *buf, int state_in, int opcode) {
    int state_out = 0;
    if(state_in) {
        sprintf(buf, ">%04X", opcode);
        return state_in-1;
    }
    int j = -1;
    for(int i=0; instructions[i].bin; i++) {
        if((opcode & instructions[i].mask) == instructions[i].bin) {
            j = i;
            break;
        }
    }
    if(j == -1) {
        sprintf(buf, ">%04X      <<<<<", opcode);
        return 0;
    }
    // Display addressing modes
    int p1=0, p2=0;
    char s1[20], s2[20];
    int count;
    int offset;
    switch(instructions[j].type) {
        case dual_op_mult_mult:
            sprintf(buf, "%-4s %s,%s", instructions[j].str,
                addr_mode(s1, opcode & 0x3F, &p1), 
                addr_mode(s2, (opcode >>6) & 0x3F, &p2));
            state_out = p1+p2;
            break;
        case dual_op_mult_wr: 
            sprintf(buf, "%-4s %s,R%d", instructions[j].str,
                addr_mode(s1, opcode & 0x3F, &p1), 
                (opcode >> 6) & 0xF);
            state_out = p1;
            break;
        case xop:
            sprintf(buf, "%-4s %s,%d ", instructions[j].str,
                addr_mode(s1, opcode & 0x3F, &p1), (opcode >> 6) & 0xF
                );
            state_out = p1;
            break;
        case single_op:
            sprintf(buf, "%-4s %s", instructions[j].str,
                addr_mode(s1, opcode & 0x3F, &p1)
                );
            state_out = p1;
            break;
        case cru_multi_bit:
            count = (opcode >> 6) & 0xF;
            sprintf(buf, "%-4s %s,%d", instructions[j].str,
                addr_mode(s1, opcode & 0x3F, &p1), 
                count ? count : 16);
            state_out = p1;
            break;
        case cru_single_bit:
            offset = ((int)opcode << (INTLEN-8)) >> (INTLEN-8);
            sprintf(buf, "%-4s %-4Xh %d", instructions[j].str, offset & 0xFFFF, offset);        
            break;
        case jumps:
            offset = ((int)opcode << (INTLEN-8)) >> (INTLEN-9);
            sprintf(buf, "%-4s %-4Xh %d", instructions[j].str, offset & 0xFFFF, offset);
            break;
        case shifts: 
            if(opcode & 0x00F0) {
                // count in the instruction
                sprintf(buf, "%-4s R%d,%d", instructions[j].str, 
                    opcode & 0xF, (opcode >> 4) & 0xF);
            } else {
                sprintf(buf, "%-4s R0,R%d", instructions[j].str, (opcode >> 4) & 0xF);
            }
            break;
        case immediates:
            sprintf(buf, "%-4s R%d,#", instructions[j].str, opcode & 0xF); 
            state_out = 1;
            break;
        case internal_immediates:
            sprintf(buf, "%-4s #", instructions[j].str); 
            state_out = 1;  // immediate follows
            break;
        case internal_store:
            sprintf(buf, "%-4s R%d", instructions[j].str, opcode & 0xF); 
            break;
        case rtwp:
            sprintf(buf, "%-4s ", instructions[j].str); 
            break;
        default:
            sprintf(buf, "????");
            break;
    }
    return state_out;
}

int main(int argc, char **argv)
{
    // Default operating mode is stateless, i.e. single words
    // are treated as opcodes and disassembled. This is good for gtkwave debugging.
    // If the parameter -s the disassembly becomes stateful.
    int stateful = 0;
    if(argc > 1 && argv[1] && argv[1][0]=='-' && argv[1][1]=='s') {
        stateful = 1;
        printf("Stateful mode\n");
    }
        
    int line = 0;
    if (stateful)
        printf(">%04X ", line++);
    int state=0;
    while(!feof(stdin)) {
        char buf[1025], buf2[1025];
        buf[0] = 0;
        fscanf(stdin, "%s", buf);
        if(buf[0]) {
            int hx;
            sscanf(buf, "%x", &hx);
            if(!stateful)
                state = 0;  // if inspecting IR register force state to 0
            state = dasm_one(buf2, state, hx);
            printf("%s", buf2);
            if (stateful) {
                if(!state)
                    printf("\n>%04X ", line++);
            } else
                printf("\n");
            
            
                
            fflush(stdout);
        }
    }
    return(0);
}
