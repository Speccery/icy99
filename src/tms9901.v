// tms9901.v
// EP 2019-10-19
// Bringing together earlier scattered code to have a clear implementation 
// of the TMS9901.
// Note: lacks the interrupt priority generation (IC lines below) to save logic
// and time as this is not required for the TI-99/4A.

module tms9901(
    input wire clk,
    input wire n_reset,
    input wire n_ce,
    input wire cruin, 
    input wire cruclk, 
    output wire cruout,
    input [4:0] S,   
    output wire n_intreq,
    // output [3:0] IC,
    // IO pins
    input wire [6:1] n_INT,     // 6 input only interrupt pins
    // These following 16 pins can be either inputs or outputs.
    // If they are ever written they become outputs, and only reset can change that.
    // Pins 7 to 15 have interrupt capability.
    output reg [15:0] POUT,    
    input wire [15:0] PIN,
    output reg [15:0] DIR   // Pin direction, 1=output
);

`define TI994A_INTERRUPTS_ONLY

// Interrupt mask bits are cru_bits[15:1] in accordance to the following table:
// 1    n_int[1]
// 2    n_int[2]
// 3    n_int[3]    (also timer interrupt)
// 4    n_int[4]
// 5    n_int[5]
// 6    n_int[6]
// 7    n_int7 /P15
// 8    n_int8 /P14
// 9    n_int9 /P13
// 10   n_int10/P12
// 11   n_int11/P11
// 12   n_int12/P10
// 13   n_int13/P9
// 14   n_int14/P8
// 15   n_int15/P7

reg [31:0] cru_bits;         // 32 write bits to 9901, when cru9901(0)='0'
reg [15:0] cru9901_clock;	 // 15 write bits of 9901 when cru9901(0)='1' (bit 0 not used here)
reg [13:0] decrementer;      // 14 bit decrementer value
reg [15:0] dec_read;         // Decrementer read register (bits 14:1 are used)
reg last_cruclk;
// BUGBUG: In an actual TMS9901 every 64th clock decrements the decrementer
// Here we use currently 8-bit counter to divide by 256.
reg [7:0]  clk_divider = 8'd0;    
reg timer_int_pending;
reg disconnect_int3 = 1'b0;

wire go_cruclk = cruclk && !last_cruclk;    // 1 clock cycle long pulse

// read logic, these are in a specific order.
wire [0:31] read_bits = { 
    cru_bits[0], n_INT[1], n_INT[2], n_INT[3], n_INT[4], n_INT[5], n_INT[6], PIN[15],
    PIN[14],     PIN[13],  PIN[12],  PIN[11],  PIN[10],  PIN[9] ,  PIN[8],   PIN[7],
    PIN[0],      PIN[1],   PIN[2],   PIN[3],   PIN[4],   PIN[5],   PIN[6],   PIN[7],
    PIN[8],      PIN[9],   PIN[10],  PIN[11],  PIN[12],  PIN[13],  PIN[14],  PIN[15]
};

wire timer_mode = cru_bits[0] == 1'b1;

assign cruout = n_ce ? 1'b1     : // Just return 1 when not selected, should be 1'bz but yosys is not cool with that
    (S == 5'd0 || S[4] == 1'b1 || !timer_mode) ? read_bits[S[4:0]] :
    (S == 5'd15 && timer_mode) ? n_intreq        : // Timer mode addr 15
    dec_read[S];

// Interrupt reguest generation, active low output. There are 15 interrupt pins.
`ifdef TI994A_INTERRUPTS_ONLY
assign n_intreq = !(
    (cru_bits[ 1] & ~n_INT[1]) ||   // n_INT 1 (peripherals on TI-99/4A)
    (cru_bits[ 2] & ~n_INT[2]) ||   // n_INT 2 (VDP on TI-99/4A)
    (cru_bits[ 3] & timer_int_pending)
    );
`else
assign n_intreq = !(
    (cru_bits[ 1] & ~n_INT[1]) ||   // n_INT 1 (peripherals on TI-99/4A)
    (cru_bits[ 2] & ~n_INT[2]) ||   // n_INT 2 (VDP on TI-99/4A)
    ((cru_bits[3]  & ~n_INT[3] & ~disconnect_int3) && cru9901_clock[14:1]==14'h0000) || // pin n_INT 3 is not an interrupt if timer is active
    (cru_bits[ 4] & ~n_INT[4]) ||   // n_INT 4,5,6
    (cru_bits[ 5] & ~n_INT[5]) ||   // n_INT 4,5,6
    (cru_bits[ 6] & ~n_INT[6]) ||   // n_INT 4,5,6
    (cru_bits[ 7] & ~PIN[15]) || (cru_bits[ 8] & ~PIN[14]) || 
    (cru_bits[ 9] & ~PIN[13]) || (cru_bits[10] & ~PIN[12]) || 
    (cru_bits[11] & ~PIN[11]) || (cru_bits[12] & ~PIN[10]) || 
    (cru_bits[13] & ~PIN[ 9]) || (cru_bits[14] & ~PIN[ 8]) || 
    (cru_bits[15] & ~PIN[ 7]) || (cru_bits[ 3] & timer_int_pending));
`endif

// output pins
genvar i;
generate
    for(i=0; i<16; i=i+1) begin : OUTPUT_PINS_BLOCK
        always @(posedge clk) begin
            POUT[i] <= DIR[i] ? cru_bits[16+i] : 1'b0;
        end
    end
endgenerate



always @(posedge clk)
begin
    if (!n_reset) begin
        DIR   <= 16'h0;  // Initially pins are inputs
        cru_bits <= 32'h0;
        last_cruclk  <= 1'b0;
        timer_int_pending <= 1'b0;
        cru9901_clock <= 16'd0;
        disconnect_int3 <= 1'b0;
    end else begin
        clk_divider <= clk_divider - 8'd1;

        last_cruclk  <= cruclk;
        if (go_cruclk && !n_ce) begin
            // Write to a register
            if (timer_mode && S[4] == 1'b0) begin
                cru9901_clock[S[3:0]] <= cruin; 
                if (S[3:0] == 4'd15 && cruin == 1'b0) begin
                    // Software reset, reset pin directions to input
                    DIR <= 16'h0; 
                    // Should we also reset interrupt masks? I do it here. However, timer values remain.
                    cru_bits <= 32'h0;
                end
            end else begin
                cru_bits[S[4:0]] <= cruin;
                if (S == 5'd3 && !timer_mode)
                    timer_int_pending <= 1'b0;  // regardless of written data interrupt is cleared.
                if (S[4] == 1'b1) begin
                    DIR[S[3:0]] <= 1'b1; // This pin became permanently an output
                end
            end 
        end
        // decrementer loaded by writing 0 to CRU bit 0 or accessing bit higher than 15
        if (go_cruclk && !n_ce && ((S == 5'b00000 && cruin == 1'b0) || S[4]==1'b1) && timer_mode) begin
            decrementer = cru9901_clock[14:1];
            cru_bits[0] <= 1'b0;
        end
        if (clk_divider == 8'd0) begin
            if (decrementer == 14'd0) begin
                decrementer = cru9901_clock[14:1];
                timer_int_pending <= 1'b1;
                disconnect_int3 <= 1'b1;
            end else if (cru9901_clock[14:1] != 14'd0) begin
                decrementer = decrementer - 14'd1;
            end
        end 
        if (!timer_mode) begin
            dec_read <= decrementer;    // The read register updated when not in timer access mode
        end
    end
end

endmodule
