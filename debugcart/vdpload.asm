* EXECUTABLE CART IMAGE
* Erik Piehl (C) 2020 October
*
* VDPTest, this is a cartridge with 5 banks.
* Each bank has this same executable in the bottom 4K, padded to 4K.
* The top 4K contain data to be written to VDP memory, basically
* the 16K VDP + regs image split to four 4K blocks and the last having
* the registers.
* Taken from a VDPDUMP.BIN file created with classic99.

       IDT  'VDPTEST'
        
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
; Switch to the graphics mode specified in ROM bank 4
        CLR   @BANK4           * Switch to ROM bank 4
        LI    R1,DATABLK
        CLR   R0
        LI    R2,8
!       SWPB  R0       ; Move VDP reg number to lower byte
        MOVB  *R1+,R0  ; Fetch register value byte
        SWPB  R0       ; Now reg num in high byte, data in low byte
        BL    @VWREG    
        AI    R0,>0100    ; Inc reg number
        DEC   R2
        JNE    -!
; Done. Setup VDP VRAM pointer to zero.
        LI   R0,0
        BL   @SETUPVDPA 
; Next go through banks 0,1,2,3 and copy 4K data from each to VRAM.
        LI    R3,BANK0
BANKLOOP:
        CLR   *R3       ; Change to a bank
        LI    R1,>1000  ; 4K data to Move
        LI    R2,DATABLK ; Source
; Loop through the block of 4K
!       MOVB  *R2+,@VDPWD 
        DEC   R1
        JNE   -!
; Done, go to next bank
        INCT  R3
        CI    R3,BANK4      ; Point to bank 4?
        JNE   BANKLOOP  ; No, go back
; Done. stop here.
STOP    JMP  STOP 

        END MAIN
