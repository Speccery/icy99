// tms9900.v
// Verilog conversion of my VHDL TMS9900 CPU core.
// Started 2019-09-02.
// 
// Intended to be synthesized with the Icestorm toolchain for the ICE40HX4K 
// (really a 8K) chip. As a verilog design should work on other FPGAs as well.
// The goal is to simplify the code where possible, but still to make a fast 
// design able to support high clock speeds.
//
// Since this is the second pass of the code, I also will try to improve the
// design for readability.

module tms9900(
    input clk, 
    input reset,
    output [15:0] addr_out,
    input  [15:0] data_in,
    output [15:0] data_out,
    output reg rd,
    output reg wr,
    output reg rd_now,
    input  cache_hit,
    input  use_ready,
    input  ready,
    output reg iaq,
    output reg as,
    input  int_req,
    input [3:0] ic03,
    output reg int_ack,
    input  cruin,
    output reg cruout,
    output cruclk,
    input  hold,
    output reg holda,
    input [7:0] waits,
    output reg stuck,
    output [15:0] ir_out,
    output [15:0] pc_ir_out,
    output [15:0] pc_ir_out2    // previous
);
localparam 	
    do_pc_read=7'd0, 		    do_alu_read=7'd1,
    do_fetch=7'd2,              do_fetch0=7'd3, 
    do_decode=7'd4,             do_branch=7'd5,
    do_stuck=7'd6,              do_read0=7'd7, 
    do_read1=7'd8,              do_read2=7'd9, 
    do_read3=7'd10,             do_write=7'd11,
    do_write0=7'd12,            do_write1=7'd13, 
    do_write2=7'd14,            do_write3=7'd15, 
    do_ir_imm=7'd16,            do_lwpi_limi=7'd17,
    do_load_imm=7'd18,          do_load_imm5=7'd19,
    do_read_operand0=7'd20,     do_read_operand1=7'd21, 
    do_read_operand2=7'd22,     do_read_operand3=7'd23, 
    do_read_operand4=7'd24,     do_read_operand5=7'd25,
    do_alu_write=7'd26,         do_dual_op=7'd27, 
    do_dual_op1=7'd28,          do_dual_op2=7'd29, 
    do_dual_op3=7'd30,          do_source_address0=7'd31, 
    do_source_address1=7'd32,   do_source_address2=7'd33, 
    do_source_address3=7'd34,   do_source_address4=7'd35, 
    do_source_address5=7'd36,   do_source_address6=7'd37,
    do_branch_b_bl=7'd38,       do_x_instruction=7'd39, 
    do_x_write0=7'd40,          do_x_fetch=7'd41,
    do_single_op_writeback=7'd42, do_rtwp0=7'd43, 
    do_rtwp1=7'd44,             do_rtwp2=7'd45, 
    do_rtwp3=7'd46,             do_shifts0=7'd47, 
    do_shifts1=7'd48,           do_shifts2=7'd49, 
    do_shifts3=7'd50,           do_shifts4=7'd51,
    do_blwp00=7'd52,            do_blwp0=7'd53, 
    do_blwp_xop=7'd54,          do_blwp1=7'd55, 
    do_blwp2=7'd56,             do_blwp3=7'd57,
    do_single_bit_cru0=7'd58,   do_single_bit_cru1=7'd59, 
    do_single_bit_cru2=7'd60,   do_ext_instructions=7'd61, 
    do_store_instructions=7'd62, do_coc_czc_etc0=7'd63, 
    do_coc_czc_etc1=7'd64,      do_coc_czc_etc2=7'd65, 
    do_coc_czc_etc3=7'd66,      do_xop=7'd67,
	do_ldcr0=7'd68,             do_ldcr00=7'd69, 
    do_ldcr1=7'd70,             do_ldcr2=7'd71, 
    do_ldcr3=7'd72,             do_ldcr4=7'd73, 
    do_ldcr5=7'd74,             do_stcr0=7'd75, 
    do_stcr6=7'd76,             do_stcr7=7'd77,
	do_stcr_delay0=7'd78,       do_stcr_delay1=7'd79,
	do_idle_wait=7'd80,         do_mul_store0=7'd81, 
    do_mul_store1=7'd82,        do_mul_store2=7'd83,
	do_div0=7'd84,              do_div1=7'd85, 
    do_div2=7'd86,              do_div3=7'd87, 
    do_div4=7'd88,              do_div5=7'd89,
    do_process_branch=7'd90,    do_mul0=7'd91,
    do_mul1=7'd92,              do_mul2=7'd93,
    do_mul3=7'd94,              do_mul4=7'd95 ;

localparam fetch_sub1=2'd1, fetch_sub2=2'd2, fetch_sub3=3'd3;

// ALU operations
localparam 
        alu_load1=4'h0, alu_load2=4'h1, alu_add =4'h2, alu_sub =4'h3, 
        alu_abs  =4'h4, alu_aor  =4'h5, alu_aand=4'h6, alu_axor=4'h7,
        alu_andn =4'h8, alu_coc  =4'h9, alu_czc =4'ha, alu_swpb=4'hb,
        alu_sla  =4'hc, alu_sra  =4'hd, alu_src =4'he, alu_srl =4'hf;

reg  [16:0] arg1;   // arg1 is 17 bits wide to support DIV steps
reg  [15:0] arg2;
reg  [3:0]  ope;
wire [15:0] alu_result;
wire alu_logical_gt, alu_arithmetic_gt;
wire alu_flag_zero, alu_flag_carry, alu_flag_overflow;
wire alu_flag_parity, alu_flag_parity_source;
reg alu_compare;

reg [15:0] addr;    // our address bus

assign addr_out = addr;
assign data_out = wr_dat;

alu9900 alu(
    // arg1, arg2, ope, alu_compare,
    // alu_result_d, 
    // alu_lgt_d, alu_agt_d, 
    // alu_flag_zero_d, alu_flag_carry_d,alu_flag_overflow_d, 
    // alu_flag_parity_d, alu_flag_parity_source_d
    .arg1(arg1), .arg2(arg2), .ope(ope), .alu_result(alu_result),
    .compare(alu_compare),
    .alu_logical_gt(alu_logical_gt), .alu_arithmetic_gt(alu_arithmetic_gt),
    .alu_flag_zero(alu_flag_zero), .alu_flag_carry(alu_flag_carry),
    .alu_flag_overflow(alu_flag_overflow), 
    .alu_flag_parity(alu_flag_parity), .alu_flag_parity_source(alu_flag_parity_source)
    );


reg operand_word;
reg  [15:0] read_byte_aligner;
reg  [15:0] ea, rd_dat;
reg  [15:0] st=0, pc, w;
reg cruclk_internal;
reg i_am_xop;
reg [6:0] cpu_state, cpu_state_next, cpu_state_operand_return;
reg read_to_arg2, set_ea_from_alu, set_dual_op_flags;
reg [15:0] wr_dat;
reg set_int_priority;
reg [15:0] reg_t, reg_t2, reg_stcr;
reg [7:0] delay_count;
reg [15:0] pc_offset;
reg [1:0] fetch_substate;
reg add_to_pc;
reg [15:0] ir;
reg [4:0] shift_count;
reg [15:0] pc_ir, pc_ir2;   
reg executing_x = 1'b0;

assign ir_out = ir;
assign pc_ir_out = pc_ir;
assign pc_ir_out2 = pc_ir2;

reg [7:0] cru_delay_spec = 8'h02;

reg mult_top_bit;

reg mul_carry;
reg [31:0] dividend;    
reg [16:0] divider_sub;

// assign cpu_state_out <= cpu_state;
// assign cpu_state_next_out <= cpu_state_next;
// assign cpu_state_operand_return_out <= cpu_state_operand_return;

//------------------------------------------------------------------------
// CRUCLK pulser
//------------------------------------------------------------------------
assign cruclk = cruclk_internal;
//reg past_cruclk = 1'b0;
//always @(negedge clk)
//begin
//    if (past_cruclk == 1'b0 && cruclk == 1'b1)
//        cruclk_out <= 1'b1;
//    else    
//        cruclk_out <= 1'b0;
//    past_cruclk <= cruclk;
//end

//------------------------------------------------------------------------
// Byte aligner
always @(operand_word, rd_dat, ea)
begin
    if (operand_word)
        read_byte_aligner <= rd_dat;
    else begin
        if(ea[0] == 1'b0 )
            read_byte_aligner <= { rd_dat[15:8], 8'h00 };
        else    
            read_byte_aligner <= { rd_dat[7:0], 8'h00 };
    end
end

reg [15:0] dest_reg_addr;
reg [5:0] operand_mode;

//------------------------------------------------------------------------
//  Divider / Multiplier as a separate entity
//------------------------------------------------------------------------
reg mpy_div_done = 1'b0;
reg mpy_div_start = 1'b0;
reg mpy_op = 1'b0;  // 0=DIV 1=MPY
reg [3:0] md_count;
reg md_step = 1'b0;
reg md_carry;
// For division, divide reg_t2:rd_dat by reg_t.
// For multiply, multiply rd_dat by reg_t.
// This block is the only one writing to dividend.
always @(posedge clk)
begin : mpy_div
    if (mpy_div_start == 1'b1) begin
        mpy_div_done <= 1'b0;
        md_count <= 4'b0000;
        dividend <= mpy_op ? { rd_dat, 16'h0000 } : { reg_t2, rd_dat };
        md_step <= 1'b1;
    end else if (!mpy_div_done) begin
        if (md_step) begin
            dividend <= { dividend[30:0], 1'b0 };
            md_carry <= dividend[31];
            divider_sub <= dividend[31 : 15] - { 1'b0, reg_t };
            md_count <= md_count - 4'h1;
        end else begin
            if(mpy_op) begin
                // MPY
                if(md_carry)
                    dividend <= dividend + { 16'h0000, reg_t };
            end else if (divider_sub[16] == 1'b0) begin 
                // DIV successful subtract
                dividend[31 : 16] <= divider_sub[15 : 0];
                dividend[0] <= 1;
            end
            if (md_count == 4'b0000)
                mpy_div_done <= 1'b1;
        end
        md_step <= !md_step;
    end
end

//------------------------------------------------------------------------
//  The Absolytely Awesome State Machine
//------------------------------------------------------------------------
always @(posedge clk)
begin
    if (reset == 1'b1) begin
        st <= 16'h0000;  // FIXME - could be removed
        pc <= 16'h1234;  // FIXME - could be removed
        stuck <= 1'b0;
        rd <= 1'b0;
        wr <= 1'b0;
        cruclk_internal <= 1'b0;
        // Prepare for BLWP from 0
        i_am_xop <= 1'b0;
        arg2 <= 16'h0000;
        ope <= alu_load2;
        cpu_state <= do_blwp00;
        // Continue with reset theme
        delay_count = 0;
        holda <= hold;   // Respect hold during reset
        set_int_priority <= 1'b0;
        int_ack <= 1'b0;
        // bring bus to a known state
        iaq <= 1'b0;
        rd_now <= 1'b0;
        as <= 1'b0;
        read_to_arg2 <= 1'b0;
        set_ea_from_alu <= 1'b0;
        set_dual_op_flags <= 1'b0;
        add_to_pc = 1'b0;
    end else begin
        // Normal execution, the following happens on every clock cycle
        add_to_pc = 0;
        
        if (set_ea_from_alu) begin
            ea <= alu_result;
            set_ea_from_alu <= 0;
        end
        
        if (set_dual_op_flags) // Set the flags for dual OP instructions from ALU outputs. Used to be done in do_dual_op3.
        begin
            set_dual_op_flags <= 0;
            // Store flags.
            st[15] <= alu_logical_gt;
            st[14] <= alu_arithmetic_gt;
            st[13] <= alu_flag_zero;
            if (ir[15:13] == 3'b101 || ir[15:13] == 3'b011) begin
                // add and sub set two more flags
                st[12] <= alu_flag_carry;
                st[11] <= alu_flag_overflow;
            end 	
            // Byte operations set parity
            if (!operand_word) begin
                // parity bit for MOVB and CB is set differently and only depends on source operand
                if (ir[15:13] == 3'b100 || ir[15:13] == 3'b110)
                    st[10] <= alu_flag_parity_source;	// MOVB, CB
                else
                    st[10] <= alu_flag_parity;
            end 
        end    

        // State changes
        case(cpu_state)
            // read cycles
			do_pc_read: begin
				    addr <= pc;
					add_to_pc = 1'b1;
					pc_offset = 16'h0002;
					as <= 1'b1;
					rd <= 1'b1;
					cpu_state <= do_read0;
                end
            do_alu_read: begin
                    addr <= alu_result;
                    as <= 1'b1;
                    rd <= 1'b1;
                    cpu_state <= do_read0;
                end
			do_read0: begin
					cpu_state <= do_read1;
					delay_count = waits;	// used to be zero (i.e. not assigned)
					as <= 1'b0;
                end
			do_read1: begin
					if (cache_hit == 1'b1) begin
                        delay_count = 0;
                        cpu_state <= cpu_state_next;
                        rd <= 1'b0;
                        rd_dat <= data_in;
                        if (read_to_arg2) begin
                            arg2 <= data_in;
                            read_to_arg2 <= 1'b0;
                        end
                    end else begin
                        if ((use_ready==1'b0 && delay_count == 8'd0) || (ready == 1'b1)) begin
                            delay_count = 8'd0;
                            cpu_state <= do_read3;  // NOTE: BYPASS do_read2
                            rd_now <= 1'b1;                            
                        end
                    end
                end
			do_read2: begin
					cpu_state <= do_read3;
					rd_now <= 1'b1;	// the next cycle will latch data from databus
                end
			do_read3: begin
                    cpu_state <= cpu_state_next;
                    rd <= 1'b0;
                    rd_dat <= data_in;
                    rd_now <= 1'b0;
                    if (read_to_arg2) begin
                        arg2 <= data_in;
                        read_to_arg2 <= 1'b0;
                    end
                end
            // write cycles
            do_write:
                begin
                    addr <= ea;
                    as <= 1'b1;
                    wr <= 1'b1;
                    cpu_state <= do_write0;
                end
            do_alu_write: begin
                addr <= alu_result;						
                // not needed in verilog implementation since wr_dat is our only write data: data_out <= wr_dat;
                as <= 1'b1;
                wr <= 1'b1;
                cpu_state <= do_write0;
                end
            do_write0:
                begin 
                    cpu_state <= do_write1; 
                    as <= 1'b0;
                    if (waits[7:1] == 7'd0)
                        delay_count = 7'd0; // minimum value
                    else
                        delay_count = waits;
                end
            do_write1:  begin   
                    if ((use_ready == 1'b0 && delay_count == 8'd0) || ready == 1'b1) begin
                        delay_count = 8'd0;
                        cpu_state <= do_write2;
                    end
                end
            do_write2:  cpu_state <= do_write3;
            do_write3:  begin
                    cpu_state <= cpu_state_next;
                    wr <= 1'b0;
                end
            do_fetch: begin
                    if (hold == 1'b1)
                        holda <= 1'b1;
                    else begin
                        holda <= 1'b0;
                        i_am_xop <= 1'b0;
                        // check interrupt request
                        if (int_req == 1'b1 && ic03 <= st[3:0]) begin
                            // interrupt taken
                            set_int_priority <= 1'b1;
                            arg2 <= { 10'b00_0000_0000, ic03, 2'b00 };
                            ope <= alu_load2;
                            cpu_state <= do_blwp00;
                            int_ack <= 1'b1;
                        end else begin
                            iaq <= 1'b1;
                            addr <= pc;
                            add_to_pc = 1'b1;
                            pc_offset = 16'h0002;
                            as <= 1'b1;
                            rd <= 1'b1;
                            cpu_state <= do_fetch0;
                            fetch_substate <= fetch_sub1;
                        end
                    end
                end
            do_fetch0: begin
                    cpu_state <= do_decode;
                    as <= 1'b0;
                    delay_count = waits;
                    executing_x <= 1'b0;
                end
            //-----------------------------------------------------------------------------
            // do_decode
            //----------------------------------------------------------------------------
            do_decode: begin
                    if ((fetch_substate == fetch_sub1 && cache_hit==1) || fetch_substate==fetch_sub3) begin
                        if (!executing_x)
                            ir = data_in;						// read done, store to instruction register
                        delay_count = 8'd0;
                        rd_now <= 0;
                        rd <= 0;
                        pc_ir2 <= pc_ir;                    // also retain earlier pc_ir
                        pc_ir <= pc;						// store increment PC for debug purposes
                        // rest of decode process.
                        operand_word <= 1;			// By default 16-bit operations.
                        iaq <= 0;
                        // Calculate immediately the source register operand addresses, so it is there at the ALU output.
                        arg1 <= { 1'b0, w };
                        arg2 <= { 11'b0000_0000_000, ir[3:0], 1'b0 };
                        ope <= alu_add;	// calculate workspace address		
                        dest_reg_addr <= w + { 11'b0000_0000_000, ir[9:6], 1'b0 };;
                        // Here operand mode is always for the source register.
                        operand_mode <= ir[5:0]; 
                        alu_compare <= 0;
                        
                        // Next analyze what instruction we got
                        // check for dual operand instructions with full addressing modes
                        if (ir[15:13] == 3'b101 || // A, AB
                            ir[15:13] == 3'b100 || // C, CB
                            ir[15:13] == 3'b011 || // S, SB
                            ir[15:13] == 3'b111 || // SOC, SOCB
                            ir[15:13] == 3'b010 || // SZC, SZCB
                            ir[15:13] == 3'b110) begin // MOV, MOVB
                            // found dual operand instruction. Get source operand.
                            operand_word <= !ir[12];
                            cpu_state <= do_alu_read;
                            if (ir[5:4] == 2'b00) begin 
                                cpu_state_next <= do_dual_op;	// skip workspace reg read cycle, do_alu_read handles this already.
                                set_ea_from_alu <= 1;
                            end else begin
                                cpu_state_next <= do_read_operand1;	// skip do_read_operand0
                                cpu_state_operand_return <= do_dual_op;
                            end
                        end else if (ir[15:12] == 4'b0001
                             && ir[11:8] != 4'hD && ir[11:8] != 4'hE && ir[11:8] != 4'hF)
                                cpu_state <= do_branch; 
                        else if(ir[15:10] == 6'b000010) begin // SLA, SRA, SRC, SRL
                            // Do all the shifts SLA(10) SRA(00) SRC(11) SRL(01), OPCODE:6 INS:2 C:4 W:4
                            shift_count <= { 1'b0, ir[7:4] };
                            cpu_state <= do_shifts0;
                        end else if (ir == 16'h0380) begin // RTWP
                            arg1 <= { 1'b0, w };
                            arg2 <= { 11'b0000_0000_000, 4'hD, 1'b0 };  // calculate of register 13 (WP)
                            ope <= alu_add;	
                            cpu_state <= do_rtwp0;
                        end else if (ir[15:8] == 8'h1D  || // SBO
                                ir[15:8] == 8'h1E  || // SBZ
                                ir[15:8] == 8'h1F)  // TB
                        begin
                            arg1 <= w;
                            arg2 <= { 11'b0000_0000_000, 4'hC, 1'b0 };
                            ope <= alu_add;
                            cpu_state <= do_alu_read;	// Read WR12
                            cpu_state_next <= do_single_bit_cru0;
                        end else if (ir == 16'h0340 || ir == 16'h0360 || ir == 16'h03C0 || ir == 16'h03A0 || ir == 16'h03E0)
                        begin
                            // external instructions IDLE, RSET, CKOF, CKON, LREX
                            cpu_state <= do_ext_instructions;
                        end else if(ir[15:4] == 12'h02c || ir[15:4] == 12'h02a) // STST, STWP
                            cpu_state <= do_store_instructions;
                        else if (ir[15:13] == 3'b001 && ir[12:10] != 3'b100 && ir[12:10] != 3'b101) begin
                            //	COC, CZC, XOR, MPY, DIV, XOP
                            if (ir[12:10] == 3'b011) begin // XOP
                                cpu_state <= do_source_address0;
                                cpu_state_operand_return <= do_xop;
                            end else begin
                                cpu_state <= do_read_operand0;
                                cpu_state_operand_return <= do_coc_czc_etc0;
                            end
                        end else if (ir[15:11] == 5'b00110) begin // LDCR, STCR
                            // set operand_word to byte mode if count of bits is 1..8
                            if (ir[9:6] == 4'b1000 || (ir[9] == 0 && ir[8:6] != 3'b000))
                                operand_word <= 0;
                            if (ir[10] == 0) begin
                                cpu_state <= do_read_operand0;
                                cpu_state_operand_return <= do_ldcr0;	// LDCR
                            end else begin
                                cpu_state <= do_source_address0;
                                cpu_state_operand_return <= do_stcr0;	// STCR
                            end
                        end else if (ir[15:4] == 12'h020 || ir[15:4] == 12'h022 || // LI, AI
                                     ir[15:4] == 12'h024 || ir[15:4] == 12'h026 || // ANDI, ORI
                                    ir[15:4] == 12'h028) begin 							// CI
                                set_ea_from_alu <= 1;
                                cpu_state <= do_pc_read;
                                cpu_state_next <= do_load_imm;
                        end else if (ir[15:9] == 7'b000_0001 && ir[4:0] == 5'b00000)
                                cpu_state <= do_ir_imm;
                        else if (ir[15:10] == 6'b00_0001) begin 
                            // Single operand instructions: BL, B, etc.
                            operand_word <= 1;
                            // If we have direct register operand, that will be in ea already. Just go direct to the destination.
                            if (ir[5:4] == 2'b00) 
                                cpu_state <= do_branch_b_bl;
                            else begin 
                                cpu_state <= do_source_address0;
                                cpu_state_operand_return <= do_branch_b_bl;
                            end
                        end else begin
                            cpu_state <= do_stuck;		// unknown instruction, let's get stuck
                        end
                    end else begin
                        // tail end of do_decode, finalize opcode fetch. we ramain in do_decode.						
                        // we did not have a cache hit - memory cycle is thus still on going, work on it.
                        case (fetch_substate)  
                            fetch_sub1: begin 
                                if ((use_ready == 1'b0 && delay_count == 8'd0) || ready == 1'b1) 
                                    fetch_substate <= fetch_sub2; 
                            end
                            fetch_sub2: begin rd_now <= 1; fetch_substate <= fetch_sub3; end
                            // fetch_sub3:	// nothing, we don't get here, this is processed at top of do_decode
                            // default:
                        endcase
                    end
                end
            //-----------------------------------------------------------------------------
            // end of do_decode.
            //-----------------------------------------------------------------------------

            //-----------------------------------------------------------
            // X instruction
            //-----------------------------------------------------------
            do_x_instruction: begin
                    // Here we process the X instruction...
                    ir              = rd_dat; // Store the opcode to IR directly
                    fetch_substate  <= fetch_sub3;
                    cpu_state       <= do_decode;
                    executing_x     <= 1'b1;
                end
            do_single_op_writeback: begin
                    // setup flags
                    if (ope != alu_swpb) begin
                        // set flags for INV, NEG, ABS, INC, INCT, DEC, DECT
                        st[15] <= alu_logical_gt;
                        st[14] <= alu_arithmetic_gt;
                        st[13] <= alu_flag_zero;
                        if (ope == alu_add || ope == alu_sub || ope == alu_abs) begin
                            st[12] <= alu_flag_carry;
                            st[11] <= alu_flag_overflow;
                        end
                        if (ope == alu_abs)
                            st[12] <= 0;			// ABS instruction always clears carry on the TMS99105, and also on classic99.
                    end 
                    // write the result
                    // inilined below. in this Verilog version wr_dat is updated.
                    // cpu_state <= do_write;	// ea still holds our address; return via write
                    cpu_state <= do_write0; addr <= ea; wr_dat <= alu_result; as <= 1; wr <= 1;
                    cpu_state_next <= do_fetch;
                end
            //-----------------------------------------------------------
            // Single operand instructions
            //-----------------------------------------------------------					
            do_branch_b_bl: begin
                // when we enter here source address is at the ALU output
                case (ir[9:6]) 
                    4'b0001: begin // B instruction
                        pc <= alu_result;	// the source address is our PC destination
                        cpu_state <= do_fetch;
                        end
                    4'b1010: begin // BL instruction.Store old PC to R11 before returning.
                        pc <= alu_result;	// the source address is our PC destination
                        wr_dat <= pc;		// capture old PC before to write data
                        arg1 <= { 1'b0, w };
                        arg2 <= 16'h0016;	// 2*11 <= 22 <= 0x16, offset to R11
                        ope <= alu_add;
                        cpu_state <= do_alu_write;
                        cpu_state_next <= do_fetch;
                        end
                    4'b0011: begin // CLR instruction
                        wr_dat <= 16'h0000;
                        cpu_state <= do_alu_write;
                        cpu_state_next <= do_fetch;
                        end
                    4'b1100: begin // SETO instruction
                        wr_dat <= 16'hFFFF;
                        cpu_state <= do_alu_write;
                        cpu_state_next <= do_fetch;
                        end
                    4'b0101: begin // INV instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'hFFFF;
                        ope <= alu_axor;
                        end
                    4'b0100: begin // NEG instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'h0000;
                        ope <= alu_sub;
                        end
                    4'b1101: begin // ABS instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'h0000;
                        ope <= alu_abs;
                        end
                    4'b1011: begin  // SWPB instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'h0000;
                        ope <= alu_swpb;
                        end
                    4'b0110: begin // INC instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'h0001;
                        ope <= alu_add;
                        end
                    4'b0111: begin  // INCT instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'h0002;
                        ope <= alu_add;
                        end
                    4'b1000: begin // DEC instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'hFFFF;	// add -1 to create DEC
                        ope <= alu_add;
                        end
                    4'b1001: begin // DECT instruction
                        ea <= alu_result;	// save address SA
                        read_to_arg2 <= 1;
                        cpu_state_next <= do_single_op_writeback;
                        cpu_state <= do_read0; addr <= alu_result; as <= 1; rd <= 1; 
                        arg1 <= 17'hFFFE;	// add -2 to create DEC
                        ope <= alu_add;
                        end
                    4'b0010: begin // X instruction...
                        ea <= alu_result;
                        cpu_state_next <= do_x_instruction;
                        addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                        end
                    4'b0000: // BLWP instruction
                        // alu_result points to new WP
                        cpu_state <= do_blwp00;
                    default: 
                        cpu_state <= do_stuck;
                    endcase
                end
            //-----------------------------------------------------------------------------
            // Branches: conditional and uncoditional
            //-----------------------------------------------------------------------------
            do_branch: begin
                    // do branching, we need to sign extend ir[7 : 0] and add it to PC and continue.
                    cpu_state <= do_process_branch; // exit via do_process_branch since the add_to_pc takes time
                    case (ir[11 : 8])
                        4'b0000: begin add_to_pc=1; end	// JMP
                        4'b0001: begin if (st[14]==0 && st[13]==0) add_to_pc = 1; end // JLT
                        4'b0010: begin if (st[15]==0 || st[13]==1) add_to_pc = 1; end // JLE
                        4'b0011: begin if (             st[13]==1) add_to_pc = 1; end // JEQ
                        4'b0100: begin if (st[15]==1 || st[13]==1) add_to_pc = 1; end // JHE
                        4'b0101: begin if (             st[14]==1) add_to_pc = 1; end // JGT
                        4'b0110: begin if (             st[13]==0) add_to_pc = 1; end // JNE
                        4'b0111: begin if (             st[12]==0) add_to_pc = 1; end // JNC
                        4'b1000: begin if (             st[12]==1) add_to_pc = 1; end // JOC (on carry)
                        4'b1001: begin if (             st[11]==0) add_to_pc = 1; end // JNO (no overflow)
                        4'b1010: begin if (st[15]==0 && st[13]==0) add_to_pc = 1; end // JL
                        4'b1011: begin if (st[15]==1 && st[13]==0) add_to_pc = 1; end // JH
                        4'b1100: begin if (             st[10]==1) add_to_pc = 1; end // JOP (odd parity)
                        default: cpu_state <= do_stuck;
                    endcase
                    pc_offset = { ir[7] , ir[7] , ir[7] , ir[7] , ir[7] , ir[7] , ir[7] , ir[7:0] , 1'b0 };
                    // note we always exit via do_process_branch                     
                end
                do_process_branch: cpu_state <= do_fetch;
            //-----------------------------------------------------------------------------
            // LWPI & LIMI
            //-----------------------------------------------------------------------------
            do_ir_imm: begin
                    if (ir[8:5] == 4'b0111 || ir[8:5] == 4'b1000) begin	// 4 LSBs don't care
                        cpu_state <= do_pc_read;
                        cpu_state_next <= do_lwpi_limi;
                    end else begin
                        cpu_state <= do_stuck;
                    end
                end
            do_lwpi_limi: begin	
                    cpu_state <= do_fetch;
                    if (ir[8 : 5] == 4'b0111)
                        w <= rd_dat;	// LWPI
                    else
                        st[3 : 0] <= rd_dat[3 : 0];	// LIMI
                end
            //-----------------------------------------------------------------------------
            // immediate instructions
            //-----------------------------------------------------------------------------
            do_load_imm: begin // LI, AI, ANDI, ORI, CI instruction here
                    // ea is already set to point to our register, and rd_dat contains the immediate value.
                    arg1 <= rd_dat;
                    if (ir[7:4] == 4'h0) begin
                        // Load immediate instruction. No need to read the previous value.
                        cpu_state <= do_load_imm5;
                        ope <= alu_load1; // LI
                    end else begin
                        // inlined read register value
                        read_to_arg2 <= 1;	// store read value to ALU arg2
                        addr <= ea; as <= 1; rd <= 1; cpu_state <= do_read0;	
                        // preconfigure ALU
                        case (ir[7:4] )
                            4'h0: ope <= alu_load1; // LI
                            4'h2: ope <= alu_add;	 // AI
                            4'h4: ope <= alu_aand;	 // ANDI
                            4'h6: ope <= alu_aor;	 // ORI
                            4'h8: begin ope <= alu_sub; alu_compare <= 1; end // CI
                            default:    cpu_state <= do_stuck;
                        endcase		
                        cpu_state_next <= do_load_imm5;
                    end 
                end

            do_load_imm5: begin//  write to workspace the result of ALU, ea still points to register
                    // let's write flags 0-2 for all instructions
                    st[15] <= alu_logical_gt;
                    st[14] <= alu_arithmetic_gt;
                    st[13] <= alu_flag_zero;
                    if (ope == alu_add ) begin
                        st[12] <= alu_flag_carry;
                        st[11] <= alu_flag_overflow;
                    end
                    
                    if (alu_compare == 0) begin
                        wr_dat <= alu_result;	
                        cpu_state <= do_write;
                        cpu_state_next <= do_fetch;
                    end else begin
                        // compare, skip result write altogether
                        cpu_state <= do_fetch;
                    end
                end

            //-----------------------------------------------------------
            // Dual operand instructions
            //-----------------------------------------------------------					
            do_dual_op: begin
                    reg_t2 <= read_byte_aligner;
                    // calculate address of destination operand
                    cpu_state <= do_source_address0;
                    cpu_state_operand_return <= do_dual_op1;
                    operand_mode <= ir[11:6];
                    
                    if (ir[11:10]== 2'b00 && operand_word) begin // pc(15:4) <= x"00d" then	// BUGBUG optimize only the test MOV
                        // optimize direct register addressing mode, avoid visit to do_source_address0.
                        ea <= dest_reg_addr;
                        if (ir[15:13] == 3'b110 && operand_word) begin
                            // We have MOV, skip reading of dest operand. We still need to move along as we need to set flags.
                            cpu_state <= do_dual_op2;
                        end else begin	// not MOV, some other dual op
                            addr <= dest_reg_addr; as <= 1; rd <= 1; cpu_state <= do_read0; 
                            cpu_state_next <= do_dual_op2;
                        end
                    end
                end
                
            do_dual_op1: begin
                    // Now ALU output has address of destination (side effects done), and source_op
                    // has the source operand.
                    // Read destination operand, except if we have MOV in that case optimized
                    ea <= alu_result;	// Save destination address
                    if (ir[15:13] == 3'b110 && operand_word) begin
                        // We have MOV, skip reading of dest operand. We still need to
                        // move along as we need to set flags.
                        // test_out <= x"DD00";
                        cpu_state <= do_dual_op2;
                    end else begin
                        // we have any of the other ones expect MOV
                        addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0; 
                        cpu_state_next <= do_dual_op2;
                    end
                end
            do_dual_op2: begin
                    // Perform the actual operation. 
                    // Handle processing of byte operations for rd_dat.
                    if (ir[15:13] == 3'b110) begin
                        arg1 <= { 1'b0, 16'h0000 };	// For proper flag behavior drive zero for MOV to arg1 
                    end else begin
                        arg1 <= { 1'b0, read_byte_aligner };
                    end
                    arg2 <= reg_t2;
                    cpu_state <= do_dual_op3;
                    alu_compare <= 0;
                    case (ir[15:13])
                        3'b101: ope <= alu_add; // A add
                        3'b100: begin ope <= alu_sub; alu_compare <= 1; end // C compare
                        3'b011: ope <= alu_sub; // S substract
                        3'b111: ope <= alu_aor;
                        3'b010: ope <= alu_andn;
                        3'b110: ope <= alu_load2;	// MOV
                        default: cpu_state <= do_stuck;
                    endcase
                    set_dual_op_flags <= 1;	// Next cycle will set the flags.
                end

            do_dual_op3: begin
                    // Store the result except with compare instruction.
                    if (ir[15:13] == 3'b100)
                        cpu_state <= do_fetch;	// compare, we are already done
                    else begin
                        // writeback result
                        if (operand_word) begin
                            wr_dat <= alu_result;
                        end else begin
                            // Byte operation.
                            if (operand_mode[5:4] == 2'b00 || ea[0]==0) begin
                                // Register operation or write to high byte. Always impacts high byte.
                                wr_dat <= { alu_result[15:8], rd_dat[7:0] };
                                // data_out <= alu_result(15:8) & rd_dat(7:0);
                            end else begin
                                // Memory operation going to low byte. High byte not impacted.
                                wr_dat <= { rd_dat[15:8], alu_result[15:8] }; 
                                // data_out <= rd_dat(15:8) & alu_result(15:8); 
                            end
                        end
                        cpu_state_next <= do_fetch;
                        addr <= ea; wr <= 1; as <= 1; cpu_state <= do_write0; // inlined do_write
                    end
                end

            //-----------------------------------------------------------
            // BLWP
            // (SA) -> WP, (SA+2) -> PC
            // R13 -> old_WP, R14 -> old_PC, R15 -> ST
            //-----------------------------------------------------------					
            do_blwp00: begin
                    holda <= 1'b0;
                    ea <= alu_result;
                    arg1 <= { 1'b0, 16'h0002 };
                    arg2 <= alu_result;
                    ope <= alu_add;
                    addr <= alu_result;
                    as <= 1'b1;
                    rd <= 1'b1;
                    cpu_state <= do_read0;
                    cpu_state_next <= do_blwp0;
                end
            do_blwp0: begin 
                    ea <= alu_result;
                    reg_t <= rd_dat;
                    arg1  <= rd_dat;
                    if (!i_am_xop) begin
                        // normal BLWP
                        arg2 <= { 11'b0000_0000_000, 4'hD, 1'b0 };
                        cpu_state_next <= do_blwp1;
                    end else begin
                        // XOP
                        arg2 <= { 11'b0000_0000_000, 4'hB, 1'b0 };
                        cpu_state_next <= do_blwp_xop; // XOP has an extra step to store EA to R11
                    end
                    ope <= alu_add;
                    addr <= alu_result; as <= 1'b1; rd <= 1'b1; cpu_state <= do_read0;
                    int_ack <= 1'b0; // if this was an interrupt vectoring event, clear the flag
                end
            do_blwp_xop: begin
                    // this phase only exists for XOP
				    // Now rd_dat is new PC, reg_t new WP, alu_result addr of new R11
					wr_dat <= reg_t2;				// Write effective address to R11
					ea     <= alu_result;
					arg1   <= 16'h0004;			// Add 4 to skip R12, point to R13 for WP storage
					arg2   <= alu_result;		// prepare for WP write, i.e. point to new R14
					cpu_state 	   <= do_write; // write effective address to new R11
					cpu_state_next <= do_blwp1;						
                end 
            do_blwp1: begin
                    // now rd_dat is new PC, reg_t new WP, alu_result addr of new R13
                    wr_dat <= w;
                    ea     <= alu_result;
                    arg1   <= 16'h0002;
                    arg2   <= alu_result;		// prepare for PC write, i.e. point to new R14
                    cpu_state 	    <= do_write; // write old WP
                    cpu_state_next  <= do_blwp2;
                end
            do_blwp2:   // This is the state we come to when coming out of reset.
                begin
                    wr_dat <= pc;
                    ea <= alu_result;
                    arg2 <= alu_result;
                    cpu_state      <= do_write;
                    cpu_state_next <= do_blwp3;
                end
            do_blwp3:
                begin 
                    wr_dat <= st;
                    ea <= alu_result;
                    arg2 <= alu_result;
                    cpu_state <= do_write;
                    cpu_state_next <= do_fetch;
                    if (set_int_priority) begin
                        st[3:0] <= ic03 - 4'h1;
                        set_int_priority <= 1'b0;
                    end
                    // do context switch
                    pc <= rd_dat;
                    w  <= reg_t;
                    if(i_am_xop)
                        st[9] <= 1'b1;
                end

            //-----------------------------------------------------------
            // RTWP
            // R13 -> WP, R14 -> PC, R15 -> ST
            //-----------------------------------------------------------					
            do_rtwp0: begin
                    // Here start first read cycle (from R13) and calculate also addr of R14
                    ea <= alu_result;		// Addr of R13
                    arg1 <= { 1'b0, 16'h0002 };
                    arg2 <= alu_result;
                    ope <= alu_add;
                    addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_rtwp1;
                end
            do_rtwp1: begin
                    w <= rd_dat;			// W from previous R13
                    ea <= alu_result;		// addr of previous R14
                    arg2 <= alu_result;	// start calculation of R15
                    addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_rtwp2;
                end
            do_rtwp2: begin
                    pc <= rd_dat;			// PC from previous R14
                    ea <= alu_result;		// addr of previous R15
                    addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_rtwp3;
                end
            do_rtwp3: begin
                    st <= rd_dat;			// ST from previous R15
                    cpu_state <= do_fetch;
                end
                
            //-----------------------------------------------------------
            // All shift instructions
            //-----------------------------------------------------------					
            do_shifts0: begin
                    ea <= alu_result;	// address of our working register
                    if (shift_count == 5'b00000) begin
                        // we need to read WR0 to get shift count
                        arg1 <= { 1'b0, w };
                        arg2 <= 16'h0000;
                        ope <= alu_add;
                        cpu_state <= do_alu_read;
                        cpu_state_next <= do_shifts1;
                    end else begin
                        // shift count is ready, it came from the instruction already.
                        // read the register.
                        addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                        cpu_state_next <= do_shifts2;
                    end
                end
            do_shifts1: begin
                    // rd_dat is now contents of WR0. Setup shift count and read the operand.
                    shift_count <= { rd_dat[3:0] == 4'h0 ? 1'b1 : 1'b0, rd_dat[3:0]};
                    addr <= ea; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_shifts2;
                end
            do_shifts2: begin 
                    // shift count is now ready. rd_dat is our operand.
                    arg2 <= rd_dat;
                    case (ir[9 : 8]) 
                        2'b00: ope <= alu_sra;
                        2'b01: ope <= alu_srl;
                        2'b10: begin ope <= alu_sla; st[11] <= 0; end	// no overflow (yet)
                        2'b11: ope <= alu_src;
                        // default:
                    endcase
                    cpu_state <= do_shifts3;
                end
            do_shifts3: begin 	// we stay here doing the shifting
                    arg2 <= alu_result;
                    st[15] <= alu_logical_gt;
                    st[14] <= alu_arithmetic_gt;
                    st[13] <= alu_flag_zero;
                    st[12] <= alu_flag_carry;
                    // For SLA, set alu_flag_overflow. We have to handle it in a special way
                    // since during multiple bit shift we cannot rely on the last value of alu_flag_overflow.
                    // st[11] has been cleared in the beginning of the shift, so we only need to set it.
                    if (ir[9 : 8] == 2'b10 && alu_flag_overflow==1)
                        st[11] <= 1;
                    if (shift_count == 5'b00001) begin 
                        ope <= alu_load2;				// pass through the previous result
                        cpu_state <= do_shifts4;	// done with shifting altogether
                    end else begin
                        cpu_state <= do_shifts3;	// more shifting to be done
                    end
                    shift_count <= shift_count - 5'b00001;
                end
            do_shifts4: begin
                    // Store the result of shifting, and return to next instruction.
                    wr_dat <= alu_result;
                    cpu_state <= do_write;
                    cpu_state_next <= do_fetch;
                end
            //-----------------------------------------------------------
            // External instructions
            //-----------------------------------------------------------
            do_ext_instructions: begin
                    // external instructions IDLE, RSET, CKOF, CKON, LREX
                    // These are all the same in that they issue a CRUCLK pulse.
                    // But high bits of address bus indicate which instruction it is.
                    if (ir == 16'h0360)
                        st[3:0] <= 16'h0000;  // RSET
                    addr[15:13] <= rd_dat[7:5];
                    delay_count = cru_delay_spec;	// 5 clock cycles, used as delay counter
                    cpu_state <= do_single_bit_cru2; // issue CRUCLK pulse
                    if (ir == 16'h0340)
                        cpu_state <= do_idle_wait; // IDLE instruction, go to idle state instead of cru stuff
                end
                
            do_idle_wait: begin
                    if (delay_count != 8'b0000_0000) 
                        cruclk_internal <= 1;
                    else begin
                        cruclk_internal <= 0;
                        // see if we should escape idle state, i.e. we get an interrupt we need to serve
                        if (int_req == 1 && ic03 == st[3:0])	// FIXME potential bug with priority check
                            cpu_state <= do_fetch;
                    end
                end
            //-----------------------------------------------------------
            // Single bit CRU instructions
            //-----------------------------------------------------------
            do_single_bit_cru0: begin
                    // contents of R12 are in rd_dat. Sign extend the 8-bit displacement.
                    arg1 <= { 1'b0, // 17th bit
                        ir[7], ir[7], ir[7], ir[7], ir[7], ir[7], ir[7], 
                        ir[7:0],  1'b0
                        } ;
                    arg2 <= rd_dat;
                    ope <= alu_add;
                    cpu_state <= do_single_bit_cru1;
                end
            do_single_bit_cru1: begin
                    addr <= { 3'b000, alu_result[12:1], 1'b0 };
                    cruout <= ir[8]; // in case of output, drive to CRUOUT the bit (SBZ, SBO)
                    cpu_state <= do_single_bit_cru2;
                    delay_count = cru_delay_spec; // cru_delay_clocks
                end
            do_single_bit_cru2: begin
                    // stay in this state until delay over. For writes drive CRUCLK high.
                    if (ir[15:8] != 8'h1F) begin // Not TB
                        // SBO or SBZ - or external instructions
                        cruclk_internal <= 1;
                    end
                    if (delay_count == 8'b0000_0000) begin
                        cpu_state <= do_fetch;
                        cruclk_internal <= 0;		// drive low, regardless of write or read. For reads (TB) this was zero to begin with.
                        if (ir[15:8] == 8'h1F) // Check if we have SBZ instruction
                            st[13] <= cruin;	// If SBZ, now capture the input bit
                    end
                end                

            //-----------------------------------------------------------
            // Store ST or W to workspace register
            //-----------------------------------------------------------
            do_store_instructions: begin // STST, STWP
                    wr_dat <= (ir[6:5] == 2'b10) ? st : w;
                    cpu_state <= do_alu_write;
                    cpu_state_next <= do_fetch;
                end
            //-----------------------------------------------------------
            // COC, CZC, XOR, MPY, DIV
            //-----------------------------------------------------------
            do_coc_czc_etc0: begin
                    // Need to read destination operand. Source operand is in rd_dat.
                    reg_t <= rd_dat;	// store source operand
                    operand_mode <= { 2'b00 , ir[9:6]};	// register operand
                    cpu_state <= do_source_address0;			// calculate address of our register
                    cpu_state_operand_return <= do_coc_czc_etc1;
                end
            do_coc_czc_etc1: begin
                    ea <= alu_result;	// store the effective address and go and read the destination operand
                    addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_coc_czc_etc2;
                end
            do_coc_czc_etc2: begin
                    arg1 <= { 1'b0, reg_t };		// source
                    arg2 <= rd_dat;	// dest
                    cpu_state <= do_stuck;
                    case (ir[12 : 10])
                        3'b000: begin // COC
                            ope <= alu_coc;
                            cpu_state <= do_coc_czc_etc3;
                            end
                        3'b001: begin // CZC
                            ope <= alu_czc;
                            cpu_state <= do_coc_czc_etc3;
                            end
                        3'b010: begin // XOR
                            ope <= alu_axor;
                            cpu_state <= do_coc_czc_etc3;
                            end
                        3'b110: begin // MPY
                                cpu_state <= do_mul0; // do_div1;
                            end
                        3'b111: begin // DIV
                            // we need here dest - source operation
                            arg1 <= { 1'b0, rd_dat };
                            arg2 <= reg_t;
                            ope <= alu_sub;		// do initial comparison
                            cpu_state <= do_div0;
                            end
                        default: // FIXME stuck here?
                            cpu_state <= do_stuck;
                    endcase
                end
            do_coc_czc_etc3: begin
                    // COC, CZC, set only flag 2. Nothing is written to destination register.
                    // XOR sets flags 0-2
                    st[13] <= alu_flag_zero;
                    if (ir[12 : 11] == 2'b00) begin
                        cpu_state <= do_fetch;			// done for COC and CZC
                    end else if (ir[12 : 11] == 2'b01) begin // XOR
                        st[15] <= alu_logical_gt;
                        st[14] <= alu_arithmetic_gt;
                        wr_dat <= alu_result;
                        cpu_state <= do_write;
                        cpu_state_next <= do_fetch;
                    end else begin
                        cpu_state <= do_stuck;
                    end
                end
            do_mul0: begin  
                    // MPY the values to multiple are in rd_dat and reg_t
                    mpy_div_start <= 1'b1;
                    mpy_op <= 1'b1;
                    cpu_state <= do_div2;    // From here MPY and DIV take the same path
                end
            do_div0: begin // division, now alu_result is arg1-arg2 i.e. dest-source
                    // reg_t <= source, rd_dat <= destination
                    // First check for overflow condition (ST4) i.e. st(11)
                    st[11] <= 0; // by default no overflow
                    if ((reg_t[15]==0 && rd_dat[15]==1) || (reg_t[15] == rd_dat[15] && alu_result[15]==0)) begin
                        st[11] <= 1;	 // overflow
                        cpu_state <= do_fetch;	// done
                    end else begin
                        // fetch the 2nd word of the dividend, first calculate it's address                            
                        reg_t2 <= rd_dat;   // store the high word
                        arg1 <= 17'h0002;
                        arg2 <= ea;
                        ope <= alu_add;
                        cpu_state <= do_alu_read;
                        cpu_state_next <= do_div1;  
                    end
                end
            do_div1: begin 
                    // Start the divider. It takes inputs from rd_dat and reg_t2:reg_t
                    mpy_div_start <= 1'b1;
                    mpy_op <= 1'b0;
                    cpu_state <= do_div2;            
                end 
            do_div2: begin 
                mpy_div_start <= 1'b0; 
                if(mpy_div_done && !mpy_div_start) 
                    cpu_state <= do_div4;
            end
            do_div4: begin
                    // done with the division or multiplication. Store the results.
                    // DIV store quotient. This operation cannot be merged with the above or we do not capture the LSB.
                    // Note that the store order depends of MPY/DIV. Perhaps this could be done better?
                    wr_dat <= mpy_op ? dividend[31:16] : dividend[15 : 0];	
                    // prepare in ALU the next address 
                    arg1 <= 17'h0002;
                    arg2 <= ea;
                    ope <= alu_add;
                    // write
                    cpu_state <= do_write;
                    cpu_state_next <= do_div5; 
                end
            do_div5: begin
                    // write remainder to memory, continue with next instruction
                    wr_dat <= mpy_op ? dividend[15:0] : dividend[31 : 16];	
                    ea <= alu_result;
                    cpu_state <= do_write;
                    cpu_state_next <= do_fetch;
                end

            //-----------------------------------------------------------
            // XOP - processed like BLWP but with a few extra steps
            //-----------------------------------------------------------
            do_xop: begin
                    // alu_result is here the effective address
                    reg_t2 <= alu_result;	// effective address on its way to R11, save to t2
                    // calculate XOP vector address
                    arg1 <= 17'h0040;
                    arg2 <= { 8'h00, 2'b00, ir[9:6], 2'b00 };	// 4*XOP number
                    ope <= alu_add;
                    cpu_state <= do_blwp00;
                    i_am_xop <= 1;
                end

            //-----------------------------------------------------------
            // LDCR and STCR
            //-----------------------------------------------------------
            do_ldcr0: begin	
                    // LDCR, now rd_dat is source operand
                    reg_t <= read_byte_aligner;	// LDCR
                    // We need to setup flags - shove the (SA) which was just read into the ALU.
                    // We perform a dummy add with zero to get the flags out.
                    arg1 <= { 1'b0, read_byte_aligner };
                    ope <= alu_load1;
                    cpu_state <= do_ldcr00;
                end
            do_ldcr00: begin
                    // Update the CPU flags ST0-ST2 and ST5 if count is <= 8
                    st[15] <= alu_logical_gt;
                    st[14] <= alu_arithmetic_gt;
                    st[13] <= alu_flag_zero;
                    if (!operand_word)
                        st[10] <= alu_flag_parity;
                    operand_mode <= 6'b001100;	// Reg 12 in direct addressing mode
                    cpu_state <= do_read_operand0;
                    cpu_state_operand_return <= do_ldcr1;
                end
                
            do_stcr0: begin
                    // STCR, here alu_result is the address of our operand.
                    // reg_t will contain the operand for OR
                    reg_t <= operand_word ? 16'h0001 : 16'h0100;
                    reg_stcr <= 16'h0000;
                    reg_t2 <= alu_result;		// Store the destination effective address
                    operand_mode <= 6'b001100;	// Reg 12 in direct addressing mode
                    cpu_state <= do_read_operand0;
                    cpu_state_operand_return <= do_ldcr1;
                end
            do_ldcr1: begin
                    // rd_dat is now R12
                    ea <= rd_dat;
                    shift_count <= { ir[9:6] == 4'b0000 ? 1'b1 : 1'b0, ir[9 : 6] };
                    cpu_state <= do_ldcr2;
                end
            do_ldcr2: begin
                    arg2 <= reg_t;
                    if (ir[10] == 0) begin
                        ope <= alu_srl;	// for LDCR,shift right	
                        cpu_state <= do_ldcr3;							
                    end else begin
                        ope <= alu_sla;	// for STCR, shift left
                        cpu_state <= do_stcr_delay0; // a few cycles delay from address
                    end
                    addr <= { 3'b000, ea[12 : 1], 1'b0 }; // "000" & alu_result(12 downto 1) & 0;
                end
            do_stcr_delay0: cpu_state <= do_stcr_delay1;
            do_stcr_delay1: cpu_state <= do_ldcr3;
            do_ldcr3: begin
                    if (ir[10] == 0) begin	// LDCR
                        cpu_state <= do_ldcr4;
                        if (operand_word)
                            cruout <= alu_flag_carry;
                        else
                            cruout <= alu_result[7];	// Byte operand
                    end else begin
                        // STCR or in the data we get; done outside the ALU just here
                        if (cruin == 1)
                            reg_stcr <= reg_stcr | reg_t;	
                        cpu_state <= do_ldcr5;	// skip creation of CLKOUT pulse
                    end
                    reg_t <= alu_result;				// store right shifted operand
                    arg1 <= 17'h0002;
                    arg2 <= ea;
                    ope <= alu_add;
                    delay_count = cru_delay_spec; // cru_delay_clocks;
                end
            do_ldcr4: begin
                    cruclk_internal <= 1;
                    cpu_state <= do_ldcr5;
                end
            do_ldcr5: begin
                    if (delay_count == 8'b0000_0000) begin
                        ea <= alu_result;
                        cruclk_internal <= 0;
                        if (shift_count == 5'b00001) begin
                            if (ir[10] == 0) 
                                cpu_state <= do_fetch;		// LDCR, we are done
                            else
                                cpu_state <= do_stcr6;		// STCR, we need to store the result
                        end else begin
                            cpu_state <= do_ldcr2;
                        end
                        shift_count <= shift_count -  5'b00001;
                    end
                end
            do_stcr6: begin
                    // STCR set flags, as in the Mister port of my code by greyrogue.
                    st[15 : 12] <= 4'b0010;
                    if (reg_stcr != 16'h0000) 
                        st[15:13] <= { 1'b1, !reg_stcr[15], 1'b0 };
                    // Writeback the result in reg_stcr. 
                    // For byte operation support, we need to read the destination before writing
                    // to it. reg_t2 has the destination address.
                    ea <= reg_t2;
                    addr <= reg_t2; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= do_stcr7;
                end
            do_stcr7: begin
                    // Ok now rd_dat has destination data from memory. 
                    // Let's merge our data from reg_stcr and write the bloody thing back.
                    if (operand_word)
                        wr_dat <= reg_stcr;
                    else begin
                        // Byte operation.
                        if (ea[0] == 0) // high byte impacted
                            wr_dat <= { reg_stcr[15 : 8], rd_dat[7 : 0] };
                        else	// low byte impacted
                            wr_dat <= { rd_dat[15 : 8],  reg_stcr[15 : 8] }; 
                    end 
                    cpu_state_next <= do_fetch;
                    cpu_state <= do_write;
                end


            //-----------------------------------------------------------
            // subprogram to calculate source operand address SA
            // This does not include reading the source operand, the address is
            // left at ALU output register alu_result
            //-----------------------------------------------------------					
            do_source_address0: begin
                    arg1 <= { 1'b0, w };
                    arg2 <= { 11'b0000_0000_000, operand_mode[3:0], 1'b0 };
                    ope <= alu_add;	// calculate workspace address
                    case (operand_mode[5:4])
                        2'b00 :// workspace register
                            cpu_state <= cpu_state_operand_return;	// return the workspace register address
                        2'b01 : begin // workspace register indirect
                            cpu_state <= do_alu_read;
                            cpu_state_next <= do_source_address1;
                            end
                        2'b10 : begin // symbolic or indexed mode
                            cpu_state <= do_pc_read;
                            if (operand_mode[3:0] == 4'b0000)
                                cpu_state_next <= do_source_address1;	// symbolic
                            else
                                cpu_state_next <= do_source_address2;	// indexed
                            end
                        2'b11 : begin // workspace register indirect with autoincrement
                            cpu_state <= do_alu_read;
                            cpu_state_next <= do_source_address4;
                            end
                        default: cpu_state <= do_stuck;
                    endcase
                end
		    do_source_address1: begin
                // Make the result visible in alu output, i.e. the contents of the memory read.
                // This is either workspace register contents in case of *Rx or the immediate operand in case of @LABEL
                arg2 <= rd_dat;
                ope  <= alu_load2;
                cpu_state <= cpu_state_operand_return;
                end
            do_source_address2: begin
                // Indexed. rd_dat is the immediate parameter. alu_result is still the address of register Rx.
                // We need to read the register and add it to rd_dat.
                reg_t <= rd_dat;
                cpu_state <= do_alu_read;
                cpu_state_next <= do_source_address3;
                end
            do_source_address3: begin
                arg1 <= { 1'b0, rd_dat };	// contents of Rx
                arg2 <= reg_t;		// @TABLE
                ope <= alu_add;
                cpu_state <= cpu_state_operand_return;
                end
            do_source_address4: begin	// autoincrement
                reg_t <= rd_dat;	// save the value of Rx, this is our return value
                arg1 <= { 1'b0, rd_dat };
                arg2 <= operand_word ? 16'h0002 : 16'h0001;
                ope <= alu_add;
                ea <= alu_result;	// save address of register before alu op destroys it					
                cpu_state <= do_source_address5;
                end
            do_source_address5: begin
                // writeback the autoincremented value
                // inlined below: wr_dat <= alu_result;
                // inlined do_write: below cpu_state <= do_write;
                wr_dat <= alu_result; addr <= ea; as <= 1; wr <= 1; cpu_state <= do_write0;
                cpu_state_next <= do_source_address6;
                end
            do_source_address6: begin
                // end of the autoincrement stuff, now put source address to ALU output
                arg2 <= reg_t;
                ope <= alu_load2;
                cpu_state <= cpu_state_operand_return;
                end
            //-----------------------------------------------------------
            // subprogram to do operand fetching, data returned in rd_dat.
            // operand address is left to EA (when appropriate)
            //-----------------------------------------------------------
            do_read_operand0: begin
                    // read workspace register. Goes to waste if symbolic mode.
                    arg1 <= { 1'b0, w };
                    arg2 <= { 11'b0000_0000_00, operand_mode[3:0], 1'b0 };
                    ope <= alu_add;	// calculate workspace address
                    cpu_state <= do_alu_read;	// read from addr of ALU output
                    cpu_state_next <= do_read_operand1;
                end
            do_read_operand1: begin
                    case (operand_mode[5:4])
                    2'b00: begin
                        // workspace register, we are done.
                        ea <= alu_result; // effective address must be stored for byte selection to work
                        cpu_state <= cpu_state_operand_return;
                        end
                    2'b01: begin
                        // workspace register indirect
                        ea <= rd_dat;
                        addr <= rd_dat; as <= 1; rd <= 1; cpu_state <= do_read0;
                        // return via operand read
                        cpu_state_next <= cpu_state_operand_return;
                        end
                    2'b10: begin
                        // read immediate operand for symbolic or indexed mode
                        reg_t <= rd_dat;	// save register value for later
                        cpu_state <= do_pc_read;
                        cpu_state_next <= do_read_operand2;
                        end
                    2'b11: begin
                        // workspace register indirect auto-increment
                        reg_t <= rd_dat;		// register value, to be left to EA
                        ea <= alu_result;		// address of register
                        arg1 <= { 1'b0, rd_dat };
                        arg2 <= operand_word ? 16'h0002 : 16'h0001;
                        ope <= alu_add;		// add for autoincrement
                        cpu_state <= do_read_operand3;
                        end
                    default: 
                        cpu_state <= do_stuck;	// get stuck, should never happen
                    endcase
                end
            do_read_operand2: begin
                    // indirect or indexed mode here
                    if (operand_mode[3:0] == 4'b0000) begin
                        // symbolic, read from rd_dat
                        ea <= rd_dat;
                        addr <= rd_dat; as <= 1; rd <= 1; cpu_state <= do_read0;
                        // return after read
                        cpu_state_next <= cpu_state_operand_return;
                    end else begin
                        // indexed, need to compute the address
                        // We need to return via an extra state (not with do_alu_read) since
                        // EA needs to be setup.
                        arg1 <= { 1'b0, rd_dat };
                        arg2 <= reg_t;
                        ope <= alu_add;
                        cpu_state <= do_read_operand5;
                    end
                end
            do_read_operand3: begin
                    // write back our result to the register
                    wr_dat <= alu_result;
                    // inlined below: cpu_state <= do_write;
                    addr <= ea; as <= 1; wr <= 1; cpu_state <= do_write0;
                    cpu_state_next <= do_read_operand4;
                end
            do_read_operand4: begin
                    // Now we need to read the actual value. And return in EA where it came from.
                    ea <= reg_t;
                    addr <= reg_t; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= cpu_state_operand_return;
                end
            do_read_operand5: begin
                    ea <= alu_result;
                    addr <= alu_result; as <= 1; rd <= 1; cpu_state <= do_read0;
                    cpu_state_next <= cpu_state_operand_return; 	// return via read
                end

            default:
                begin
                    stuck <= 1'b1;
                    holda <= hold;   // Respect hold during stuck so that we can debug with DMA
                end
        endcase

        // decrement shift count if necessary
        // if (cpu_state == do_div2 || (cpu_state == do_ldcr5 && delay_count == 8'h00))
        //     shift_count <= shift_count - 1;

        if (delay_count)
            delay_count = delay_count -  8'd1;
        
        if (add_to_pc) 
            pc <= pc + pc_offset;
        
    end
end

endmodule
