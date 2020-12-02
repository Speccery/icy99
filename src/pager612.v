// pager612.v
//
// Erik Piehl (C) 2020 based on my earlier VHDL code

module pager612(
  input wire clk,
  input wire [15:12] abus_high,
  input wire [3:0] abus_low,
  input wire [11:0] dbus_in,
  output wire [11:0] dbus_out,
  input wire mapen,
  input wire write_enable,
  input wire page_reg_read,
  output wire [11:0] translated_addr,
  input wire access_regs
);

// 1 = enable mapping
// 0 = write to register when sel_regs = 1
// 0 = read from register when sel_regs = 1
// 1 = read/write registers

reg [11:0] regs[0:15];

  always @(posedge clk) begin
    if(access_regs == 1'b1 && write_enable == 1'b1) begin
      // write to paging register
      regs[abus_low[3:0]] <= dbus_in;
      // EP simplified for Verilog conversion
    end
  end

  assign translated_addr = mapen == 1'b1 && access_regs == 1'b0 ? 
    regs[abus_high[15:12]] :      // mapping on 
    {8'h00,abus_high[15:12]};    // mapping off
  assign dbus_out = (page_reg_read == 1'b1 && access_regs == 1'b1) ? regs[abus_low[3:0]] : 16'hBEEF;

endmodule
