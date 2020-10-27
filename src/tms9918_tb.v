// tms9918_tb.v
`timescale 1ns / 1ns

module tms9918_tb();

reg clk=1'b0, reset=1'b1, 
    mode=1'b0;  // 1=reg 0=memory
reg [7:0] vdp_addr;
reg [7:0] vdp_data_in;
wire [15:0] vdp_data_out;
reg wr=1'b0;
reg rd=1'b0;
wire vga_vsync, vga_hsync;
wire debug1, debug2, int_out;
wire [2:0] vga_red, vga_green;
wire [1:0] vga_blue;

reg [7:0] status;

tms9918 DUT(
    .clk(clk),
    .reset(reset),
    .mode(mode),
    .addr(vdp_addr),
    .data_in(vdp_data_in),
    .data_out(vdp_data_out),
    .wr(wr),
    .rd(rd),
    .vga_vsync(vga_vsync),
    .vga_hsync(vga_hsync),
    .debug1(debug1),
    .debug2(debug2),
    .int_out(int_out),
    .vga_red(vga_red),
    .vga_green(vga_green),
    .vga_blue(vga_blue)
);

// 25MHz clock, 40 ns cycle time, toggle every half cycle
always #20 clk = !clk;   

reg [7:0] my_count = 0;

reg [7:0] loop;

initial begin
    // EP testing location of vcd file - put it to /tmp so it does not get synced by Dropbox
    $dumpfile("sim-tms9918_tb.lxt"); // iverilog -lxt2 argument
//    $dumpfile("/tmp/tms9918_tb.vcd");
    $dumpvars(0, tms9918_tb);
    $display("tms9918_tb started");
    #500 reset = 1'b0;
    #500

    // Initialize the VDP
    vdp_init();

    // Write one font description to 0x800
    mode = 1;
    vdp_write(0, 8'h00);
    vdp_write(0, 8'h40 | 8'h08);    // Setup write to 0x0800
    @(posedge clk)
      ;
    mode = 0;
  /*
    vdp_write(0, 8'b0000_0000); // write the actual data
    vdp_write(0, 8'b0111_0000); 
    vdp_write(0, 8'b1000_1000); 
    vdp_write(0, 8'b1111_1000);
    vdp_write(0, 8'b1000_1000); 
    vdp_write(0, 8'b1000_1000);
    vdp_write(0, 8'b1000_1000); 
    vdp_write(0, 8'b1000_1000);

    // Write the first row of characters
    mode = 1;
    vdp_write(0, 8'h00);
    vdp_write(0, 8'h40 | 8'h00);    // Setup write to 0x0000

    mode = 0;
    write_zeros(80);  // write 80 zero bytes.
  */
    // Multicolor mode testing write some stuff to 1000 and to 800
    // Write pointer already at 800, i.e. character table
      vdp_write(0,8'hff);
      vdp_write(0,8'h56); // EPEP 8'hff);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55); // byte 807
      vdp_write(0,8'hff); // byte 808
      vdp_write(0,8'hff);
      vdp_write(0,8'h54);
      vdp_write(0,8'h55);
      vdp_write(0,8'h55);
      vdp_write(0,8'hfe);
      vdp_write(0,8'hee);
      vdp_write(0,8'h54); // byte 80f
      // few more to 830
      write_zeros(32);
      vdp_write(0,8'hff); // 830
      vdp_write(0,8'hee); 
      vdp_write(0,8'hee); 
      vdp_write(0,8'hee); 
      vdp_write(0,8'hee); // 834
      vdp_write(0,8'hee); 
      vdp_write(0,8'hee); 
      vdp_write(0,8'h54); // 837 
      // few more to 860
      write_zeros(32+8);
      vdp_write(0,8'hfe); // 860
      vdp_write(0,8'hee); 
      vdp_write(0,8'h44); 
      vdp_write(0,8'h45); 
      vdp_write(0,8'h45); // 864
      vdp_write(0,8'h45); 
      vdp_write(0,8'h45); 
      vdp_write(0,8'h45); // 867 
      // few more to 890
      write_zeros(32+8);
      vdp_write(0,8'h51); // 890
      vdp_write(0,8'h41); 
      vdp_write(0,8'h41); 
      vdp_write(0,8'h51); 
      vdp_write(0,8'h51); // 894
      vdp_write(0,8'h51); 
      vdp_write(0,8'h51); 
      vdp_write(0,8'h51); // 897 

    // Ok next write to name table at 1000 in this mode
      vdp_set_write_addr(14'h1000);
      #100
    // and write a few bytes
      vdp_write(0,8'h00);
      vdp_write(0,8'h06);
      vdp_write(0,8'h0c);
      vdp_write(0,8'h12);

    // Setup sprite attribute table to test 5th sprite on the line detection
    // COINC detection (with only 2 sprites)
    vdp_set_write_addr(14'h1300);
    //               Y      X      Name   Color
    vdp_write_sprite(8'hFE, 8'hFF, 8'd00, 8'h03); // Sprite 0
    vdp_write_sprite(8'hFE, 8'hFF, 8'd00, 8'h03); // Sprite 1
    // Sprite 2 is the stop marker
    vdp_write_sprite(8'hD0, 8'd10, 8'd00, 8'h03); // Sprite 2
    // vdp_write_sprite(8'd16, 8'd10, 8'd00, 8'h03); // Sprite 2
    // vdp_write_sprite(8'd16, 8'd10, 8'd00, 8'h03); // Sprite 3
    // vdp_write_sprite(8'd20, 8'd10, 8'd00, 8'h03); // Sprite 4
    // vdp_write_sprite(8'd50, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd50, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd50, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd50, 8'd10, 8'd00, 8'h03); // Sprite 8
    // vdp_write_sprite(8'd50, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03); // Sprite 16
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03); // Sprite 24
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03);
    // vdp_write_sprite(8'd80, 8'd10, 8'd00, 8'h03); // Sprite 31

    // Setup sprites, 16x16, so we need four characters.
    // Sprite pattern table at >1800
    vdp_set_write_addr(14'h1800);
    vdp_write(0, 8'hFC);  // top left corner of 16x16 sprite
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80); // byte 7
    vdp_write(0, 8'h80); // byte 8 // bottom left corner of 16x16 sprite
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'h80);
    vdp_write(0, 8'hFC); // byte 15
    vdp_write(0, 8'h3F); // byte 16 // top right corner of 16x16 sprite
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01); // byte 23
    vdp_write(0, 8'h01); // byte 24 // bottom right corner of 16x16 sprite
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h01);
    vdp_write(0, 8'h3F); // byte 31


    // Test memory operations
    vdp_set_write_addr(14'h1234);
    vdp_write(0, 8'h5a); // write the actual data
    vdp_write(0, 8'hee);    // write second databyte
    #100
    // prepare to read back the data
    vdp_set_read_addr(14'h1234);

    #50 rd = 1'b1;
    #150 $display("data read %x, expected 5A\n", vdp_data_out[15:8]);
    rd = 1'b0;

    #50 rd = 1'b1;
    #150 $display("data read %x, expected EE\n", vdp_data_out[15:8]);
    rd = 1'b0;

    #17_000_000  ; // wait 17 ms

    for(loop=0; loop<20; loop++) begin
      // Read status register
      mode = 1;
      #50 rd = 1'b1;
      #150 status = vdp_data_out[15:8];
      $display("status=%x  %d", status, loop);
      rd = 1'b0;
      #50000;
    end
    // #100000
    #20000000

    $finish;
end


  task vdp_write;
    input [7:0] waddr;
    input [7:0] wdata;
  
    begin 
        wr = 1'b0;
        vdp_data_in = wdata;
        vdp_addr = waddr;
        @(negedge clk)
          ;
        wr = 1'b1;
        @(posedge clk)
          ;
        wr = 1'b0;
        @(posedge clk)
          ;
        #50;
    end
  endtask

  // Write a sprite definition. VDP RAM address needs to be set first.
  task vdp_write_sprite;
    input [7:0] ypos;
    input [7:0] xpos;
    input [7:0] char;
    input [7:0] color;

    begin
      vdp_write(0, ypos);
      vdp_write(0, xpos);
      vdp_write(0, char);
      vdp_write(0, color);
    end
  endtask

  task vdp_set_write_addr;
    input [13:0] addr;
    begin
      mode = 1;
      vdp_write(0, addr[7:0]);
      vdp_write(0, { 2'b01, addr[13:8] });    
      mode = 0;
    end
  endtask

  task vdp_set_read_addr;
    input [13:0] addr;
    begin
      mode = 1;
      vdp_write(0, addr[7:0]);
      vdp_write(0, { 2'b00, addr[13:8] });    
      mode = 0;
    end
  endtask

  task write_zeros;
    input[7:0] count;
    reg[7:0] i;
    begin
      for(i=0; i<count; i++)
        vdp_write(0,0);
    end
  endtask

  task vdp_init;
    begin
      mode = 1;  // Basically the address input, register access
/*
      // Init as TurboForth, 40 column text mode.
      vdp_write(0, 8'h00);    vdp_write(0, 8'h80);  // Reg 0
      vdp_write(0, 8'hF0);    vdp_write(0, 8'h81);  // Reg 1
      vdp_write(0, 8'h00);    vdp_write(0, 8'h82);  // Reg 2
      vdp_write(0, 8'h0E);    vdp_write(0, 8'h83);  // Reg 3
      vdp_write(0, 8'h01);    vdp_write(0, 8'h84);  // Reg 4
      vdp_write(0, 8'h06);    vdp_write(0, 8'h85);  // Reg 5
      vdp_write(0, 8'h00);    vdp_write(0, 8'h86);  // Reg 6
      vdp_write(0, 8'hF4);    vdp_write(0, 8'h87);  // Reg 7
*/    

/*
      // Init as in TI Invaders
      // regs= [ 0x00, 0xE2, 0xF0, 0x0E, 0xF9, 0x86, 0xF8, 0xF1 ]
      vdp_write(0, 8'h00);    vdp_write(0, 8'h80);  // Reg 0
      vdp_write(0, 8'hE2);    vdp_write(0, 8'h81);  // Reg 1
      vdp_write(0, 8'hF0);    vdp_write(0, 8'h82);  // Reg 2
      vdp_write(0, 8'h0E);    vdp_write(0, 8'h83);  // Reg 3
      vdp_write(0, 8'hF9);    vdp_write(0, 8'h84);  // Reg 4
      vdp_write(0, 8'h86);    vdp_write(0, 8'h85);  // Reg 5
      vdp_write(0, 8'hF8);    vdp_write(0, 8'h86);  // Reg 6
      // Changed to F2 to have a different color for border than black
      vdp_write(0, 8'hF2);    vdp_write(0, 8'h87);  // Reg 7
*/
      // Init as Megademo multicolor rotozoomer
      vdp_write(0, 8'h00);    vdp_write(0, 8'h80);  // Reg 0
      vdp_write(0, 8'hEA);    vdp_write(0, 8'h81);  // Reg 1
      vdp_write(0, 8'h04);    vdp_write(0, 8'h82);  // Reg 2
      vdp_write(0, 8'h00);    vdp_write(0, 8'h83);  // Reg 3
      vdp_write(0, 8'h01);    vdp_write(0, 8'h84);  // Reg 4
      vdp_write(0, 8'h26);    vdp_write(0, 8'h85);  // Reg 5
      vdp_write(0, 8'h03);    vdp_write(0, 8'h86);  // Reg 6
      vdp_write(0, 8'h00);    vdp_write(0, 8'h87);  // Reg 7


    end
  endtask

endmodule
