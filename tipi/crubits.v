`ifndef _crubits_vh_
`define _crubits_vh_

// 4 bits of CRU
module crubits(
    // select
    input [0:3]cru_base,
    // TI clock input
    input ti_cru_clk,
	 // TI mem enable (when high, not a memory operation
	 input ti_memen,
	 // FPGA synchronous clock
	 input clk,
    // cru_address
    input [0:14]addr,
    // input
    input ti_cru_out,
	 // input to TMS9900 to allow reading curring addressed bit
	 output ti_cru_in,
    // bits
    output [0:3]bits
);

reg [0:3] bits_q;
reg last_cruclk;

always @(posedge clk) begin

  if (!last_cruclk && ti_cru_clk && (addr[0:3] == 4'b0001) && (addr[4:7] == cru_base)) begin 
    if (addr[8:14] == 7'h00) bits_q[0] <= ti_cru_out;
    else if (addr[8:14] == 7'h01) bits_q[1] <= ti_cru_out;
    else if (addr[8:14] == 7'h02) bits_q[2] <= ti_cru_out;
    else if (addr[8:14] == 7'h03) bits_q[3] <= ti_cru_out;
  end
  last_cruclk <= ti_cru_clk;
end

assign bits = bits_q;

// Here we just show the relevant bit. The higher level logic uses it when relevant.
// There is no way of knowing when CRU bits are read by the CPU, so reading cannot cause state changes.
assign ti_cru_in = bits_q[ addr[13:14] ];

endmodule

`endif 
