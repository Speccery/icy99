* EXECUTABLE CART IMAGE
* Erik Piehl (C) 2020 December
*
* VDP9938.ASM
*
* Try out the VDP9938 registers.

       IDT  'VDP9938'
        
VDPWD  EQU  >8C00             * VDP write data
VDPWA  EQU  >8C02             * VDP set read/write address
VDPRD  EQU  >8800             * VDP read data
VDPPTR EQU  >8890             * VDP extension: VRAM address pointer
BANK0  EQU  >6000
BANK4  EQU  >6008
DATABLK EQU >7000             * 

*---------------------------------------------
* Locations in workspace RAM.
WRKSP  EQU  >8300             * Workspace memory in fast RAM (for paging tests)
R0LB   EQU  WRKSP+1           * Register zero low byte address
*---------------------------------------------

	 EVEN

*---------------------------------------------
* Set VDP read address from R0
*---------------------------------------------
VDPREADA      
      ANDI  R0,>3FFF          * make sure it is a read command
      SWPB  R0
      MOVB  R0,@VDPWA      		* Send low byte of VDP RAM write address
      SWPB  R0
      MOVB  R0,@VDPWA         * Send high byte of VDP RAM write address
      RT
      
*---------------------------------------------
* Set VDP address from R0
*---------------------------------------------
SETUPVDPA
      SWPB  R0
      MOVB  R0,@VDPWA      		* Send low byte of VDP RAM write address
      SWPB  R0
      ORI   R0,>4000          * Set read/write bits 14 and 15 to write (01)
      MOVB  R0,@VDPWA         * Send high byte of VDP RAM write address
      RT

*---------------------------------------------
* Write VDP register
*---------------------------------------------
VWREG   ORI R0,>8000
CMD     SWPB R0   
        MOVB R0,@>8C02
        SWPB R0       
        MOVB R0,@>8C02
        B *R11

*---------------------------------------------
* MAIN
*---------------------------------------------
MAIN    LIMI 0                 * Disable interrupts
        LWPI WRKSP             * Load the workspace pointer to fast RAM
        LI    R1,VDPMODE
!       MOVB  *R1+,R0       ; Register number
        SWPB  R0
        MOVB  *R1+,R0       ; Data to register
        SWPB  R0
        CI    R0,>FFFF
        JEQ   REGS_DONE
        BL    @VWREG
        JMP   -!    
; Done. Setup VDP VRAM pointer to zero.
REGS_DONE
        BL   @COPY_FONTS
; Write a string to VRAM 30 times
        LI   R2,0   ; our VRAM destination address
        LI   R3,0   ; line counter
GO:
        MOV  R2,R0
        BL   @SETUPVDPA 
        CLR  R0
        LI   R1,VDPTEXT
!       MOVB *R1+,@VDPWD
        JNE  -!
; Write an increasing character at the END
        MOV  R3,R4
        SWPB R4
        AI   R4,' '*256
        MOVB R4,@VDPWD

        AI   R2,80      ; Advance to next line

        INC  R3
        CI   R3,30
        JNE GO

; Test the new CPU instruction MOVU and see what happens.
; First write some hex test stuff
        LI  R0,20
        BL  @SETUPVDPA
        LI  R0,0
        BL  @HEX_R0
        LI  R0,>DEAD
        BL  @HEX_R0
        LI  R0,>AA55
        BL  @HEX_R0

; Go to next line and test MOVU
        LI  R0,100
        BL  @SETUPVDPA
        LI  R3,HEXTEXT
        LI  R5,0        ; Byte operations
        DATA >038B      ; MOVU *R3,R0
        BL   @HEX_R0
        INC  R3
        DATA >38B       ; MOVU *R3,R0
        BL   @HEX_R0
        INC  R3
        DATA >38B       ; MOVU *R3,R0
        BL   @HEX_R0

        LI  R5,>100     ; Word operations
        DATA >38B       ; MOVU *R3,R0
        BL  @HEX_R0
        INC R3
        DATA >38B       ; MOVU *R3,R0
        BL  @HEX_R0
        INC R3
        DATA >38B       ; MOVU *R3,R0
        BL  @HEX_R0
        INC R3
        DATA >38B       ; MOVU *R3,R0
        BL  @HEX_R0

        LI  R2,':'*256
        MOVB R2,@VDPWD

        ; test MOVU *R0,R0
        LI  R0,HEXTEXT+9
        DATA >388
        BL  @HEX_R0
        ; test MOVU *R1,R0
        LI  R1,HEXTEXT+10
        DATA >389
        MOV R1,R8       ; Save to R8, since HEX_R0 will mess up R1
        BL @HEX_R0
        MOV R8,R0
        BL @HEX_R0
        ; Display finally base address of HEXTEXT
        LI R0,HEXTEXT
        BL @HEX_R0
        ; One more test, with single negative byte, to see sign extension
        LI R1,TEST82
        CLR R5
        DATA >389       ; MOVU *R1,R0
        BL @HEX_R0

; Wait a little bit
        LI R1,250
LP2:    CLR R2
LP1:    DEC R2
        JNE LP1
        DEC R1
        JNE LP2

; Jump back to ROM
        BLWP @0

HEX_R0: ; Display contents of R0 in hex.
        MOV     R0,R2
        SRL     R2,12
        MOVB    @HEXTEXT(R2),@VDPWD     ; Write to VDP memory
        MOV     R0,R2
        SRL     R2,8
        ANDI    R2,>000F
        MOVB    @HEXTEXT(R2),@VDPWD     ; Write to VDP memory
        MOV     R0,R2
        SRL     R2,4
        ANDI    R2,>000F
        MOVB    @HEXTEXT(R2),@VDPWD     ; Write to VDP memory
        MOV     R0,R2
        ANDI    R2,>000F
        MOVB    @HEXTEXT(R2),@VDPWD     ; Write to VDP memory
        MOVB    @HEXTEXT+16(R2),@VDPWD  ; write space
        RT
        

COPY_FONTS:
        MOV R11,R9
* copy fonts from GROMs to pattern table
        LI      R0,>6B4                                         * setup GROM source address of font table
        MOVB    R0,@>9C02
        SWPB    R0
        MOVB    R0,@>9C02
        LI      R0,>800+(32*8)          * destination address in VRAM
        BL      @SETUPVDPA
        LI      R0,62                                                   * 62 characters to copy
        CLR     R2
!ch2
        LI      R1,7                                                    * 7 bytes per char
!char
        MOVB    @>9800,@VDPWD                   * move byte from GROM to VDP
        DEC     R1
        JNE     -!char
        MOVB    R2,@VDPWD                                 * 8th byte just zero
        DEC     R0
        JNE     -!ch2
        B       *R9

        TEXT   'MARKER'
; test code to go to ROM 07E0 to handle VDP indirect / direct access using my custom instruction.
label_07e0:
        JEQ     do_indirect
do_job:        
        INCT    R4
        MOVB    @>83E3,*R15         ; Write address VDP
        MOVB    R1,*R15
        SLA     R0,8
        MOVB    @>FBFE(R15),R0      ; Data in R0
        MOVB    R5,R5              ; Word?
        JEQ     do_byte
        MOVB    @>FBFE(R15),@>83E1  ; 2nd byte in R
        B       *R11
do_byte:
        SRA     R0,8
        B       *R11

do_indirect:
        MOVB @>8300(R1),R0          ; Fetch value
        MOVB @>8301(R1),@>83E1
        MOV  R0,R1                  ; Value in R1
        jmp  do_job 


VDPMODE BYTE 0,>04  ; 04=80 columns mode >00
        BYTE 1,>F0
        BYTE 2,>00
        BYTE 3,>0E
        BYTE 4,>01
        BYTE 5,>06
        BYTE 6,>00
        BYTE 7,>F4
        BYTE 63,>FF ; Enable 9938 MODE
        BYTE 9,>80  ; 26.5 lines mode
;        BYTE 49,>40  ; F18A 30 lines mode
        BYTE >FF,>FF

    EVEN
VDPTEXT TEXT 'HELLO'
        BYTE 0,0,0
HEXTEXT TEXT '0123456789ABCDEF '
        EVEN
TEST82  BYTE >82,0

        END MAIN
