//--------------------------------------------------------------------------------
// serloader.vhd
//
// State machine for commands received over a serial port.
// This file is part of the ep994a design, a TI-99/4A clone 
// designed by Erik Piehl in October 2016.
// Erik Piehl, Kauniainen, Finland, speccery@gmail.com
//
// This is copyrighted software.
// Please see the file LICENSE for license terms. 
//
// NO WARRANTY, THE SOURCE CODE IS PROVIDED "AS IS".
// THE SOURCE IS PROVIDED WITHOUT ANY GUARANTEE THAT IT WILL WORK 
// FOR ANY PARTICULAR USE. IN NO EVENT IS THE AUTHOR LIABLE FOR ANY 
// DIRECT OR INDIRECT DAMAGE CAUSED BY THE USE OF THE SOFTWARE.
//
// Synthesized with Xilinx ISE 14.7.
//--------------------------------------------------------------------------------

module serloader(
  input wire clk,
  input wire rst,
  output wire tx,
  input wire rx,
  input wire spi_cs_n,
  input wire spi_clk,
  input wire spi_mosi,
  output wire spi_miso,
  output wire spi_rq,
  output wire [31:0] mem_addr,
  output wire [7:0] mem_data_out,
  input wire [7:0] mem_data_in,
  output reg mem_read_rq,
  input wire mem_read_ack,
  output wire mem_write_rq,
  input wire mem_write_ack
);

parameter cfg_spi_memloader=1'b0;
// SPI interface begin
// spi request - currently used for debugging.
// SPI interface end



parameter [4:0]
  idle = 0,
  set_mode = 1,
  do_auto_inc = 2,
  set_count_0 = 3,
  set_count_1 = 4,
  rd_count_1 = 5,
  rd_count_2 = 6,
  wr_a0 = 7,
  wr_a1 = 8,
  wr_a2 = 9,
  wr_a3 = 10,
  wr_dat0 = 11,
  wr_dat1 = 12,
  wr_dat2 = 13,
  wr_dat_inc = 14,
  rd_dat0 = 15,
  rd_dat1 = 16,
  rd_dat2 = 17,
  rd_dat_inc = 18;

reg [4:0] state;
reg [4:0] return_state;  // return state after autoincrement operation
reg [7:0] ab0; reg [7:0] ab1; reg [7:0] ab2; reg [7:0] ab3;
reg [7:0] rx_byte_latch;
reg rx_byte_ready;
reg [7:0] tx_data_latch;
reg [7:0] wr_data_latch;  //	signal mychar 			: integer range 0 to 255;
wire [7:0] mychar;  // datatype change for vhd2vl
reg [1:0] mode;  // repeat mode, autoincrement mode
reg [15:0] rpt_count;  // general communication signals, connected to either UART or SPI
wire [7:0] rx_data;  // data from serial port
wire rx_new_data;
wire [7:0] tx_data;  // data to serial port
reg tx_now;  // transmit tx_data NOW
wire tx_busy;  // transmitter is busy
// uart routing
wire [7:0] uart_rx_data;  // data from serial port
wire uart_rx_new_data;
wire uart_tx_now;  // transmit tx_data NOW
wire uart_tx_busy;  // transmitter is busy
// SPI routing
wire [7:0] spi_rx_data;  // data from serial port
wire spi_rx_ready;
wire [7:0] spi_tx_data;  // data to serial port
wire spi_tx_now;  // transmit tx_data NOW
wire spi_tx_busy;  // transmitter is busy
wire [15:0] cnt_minus1;
reg [3:0] ack_w_high;
reg mem_write_rq_state;
reg prev_ack;  // debugging signal
//-----------------------------------------------------------------------------
// my own SPI receiver
//-----------------------------------------------------------------------------

  assign tx_data = tx_data_latch;
  assign mem_addr = {ab3,ab2,ab1,ab0};
  assign mem_data_out = wr_data_latch;
  //	mychar <= to_integer(unsigned(rx_byte_latch));
  assign mychar = rx_byte_latch;
  assign mem_write_rq = mem_write_rq_state;
  // cnt_minus1 <= std_logic_vector(to_unsigned(to_integer(unsigned(rpt_count)) - 1, cnt_minus1'length));
  assign cnt_minus1 = (rpt_count) - 16'd1;

  assign rx_data 	   = cfg_spi_memloader ? spi_rx_data  : uart_rx_data;
  assign rx_new_data = cfg_spi_memloader ? spi_rx_ready : uart_rx_new_data;
  assign tx_busy		 = cfg_spi_memloader ? spi_tx_busy  : uart_tx_busy;
  assign uart_tx_now = !cfg_spi_memloader ? tx_now		  : 1'b0;
  assign spi_tx_now  = cfg_spi_memloader ? spi_tx_now   : 1'b0;

  always @(posedge clk, posedge rst) begin : P1
    reg [31:0] k;
    reg [31:0] kbits;
    reg [15:0] k16;
    reg [31:0] cnt;
    reg [15:0] cnt16;

    if(rst == 1'b1) begin
      state <= idle;
      ab0 <= {8{1'b0}};
      ab1 <= {8{1'b0}};
      ab2 <= {8{1'b0}};
      ab3 <= {8{1'b0}};
      mem_read_rq <= 1'b0;
      mem_write_rq_state <= 1'b0;
      rx_byte_ready <= 1'b0;
      mode <= 2'b00;
      ack_w_high <= 4'd0;
    end else begin
      tx_now <= 1'b0;
      // assume nothing is sent, this may change below
      if(rx_new_data == 1'b1) begin
        // we got a byte from serial port. Latch it. 
        // The state machine will eat it later.
        rx_byte_latch <= rx_data;
        rx_byte_ready <= 1'b1;
      end
      // for how many cycles is the memory requst high *after* getting the ack?
      prev_ack <= mem_write_ack;
      if(prev_ack == 1'b0 && mem_write_ack == 1'b1) begin
        ack_w_high <= 4'd0;
      end
      else if(mem_write_rq_state == 1'b1) begin
        ack_w_high <= ack_w_high + 4'd1;
      end
      if(rx_byte_ready == 1'b1) begin
        case(state)
        idle : begin
          case(mychar)
          8'h2e : begin
            // .
            if(tx_busy == 1'b0) begin
              tx_data_latch <= 46;
              // echo back .
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h41 : begin
            state <= wr_a0;
            // A
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h42 : begin
            state <= wr_a1;
            // B
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h43 : begin
            state <= wr_a2;
            // C
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h44 : begin
            state <= wr_a3;
            // D
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h45 : begin
            // E
            if(tx_busy == 1'b0) begin
              tx_data_latch <= ab0;
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h46 : begin
            // F
            if(tx_busy == 1'b0) begin
              tx_data_latch <= ab1;
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h47 : begin
            // G
            if(tx_busy == 1'b0) begin
              tx_data_latch <= ab2;
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h48 : begin
            // H
            if(tx_busy == 1'b0) begin
              tx_data_latch <= ab3;
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h21 : begin
            // ! write byte
            state <= wr_dat0;
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h40 : begin
            // @ read byte
            state <= rd_dat0;
            rx_byte_ready <= 1'b0;
            // char consumed
          end
          8'h2B : begin
            // + increment lowest address byte
            rx_byte_ready <= 1'b0;
            // char consumed
            ab0 <= (ab0) + 8'd1;
          end
          8'h4D : begin
            // set mode 'M'
            rx_byte_ready <= 1'b0;
            state <= set_mode;
          end
          8'h4E : begin
            // read mode 'N'
            if(tx_busy == 1'b0) begin
              tx_data_latch <= {4'h3,2'b00,mode};
              // '0', '1', '2' or '3' as ASCII
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h56 : begin
            // get version V
            if(tx_busy == 1'b0) begin
              tx_data_latch <= 8'h30;
              // '0'
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h54 : begin
            // 'T' set 16-bit repeat count
            rx_byte_ready <= 1'b0;
            state <= set_count_0;
          end
          8'h50 : begin
            // 'P' get repeat count (low, high)
            if(tx_busy == 1'b0) begin
              tx_data_latch <= rpt_count[7:0];
              tx_now <= 1'b1;
              state <= rd_count_1;
              rx_byte_ready <= 1'b0;
              // Char consumed.
            end
          end
          8'h51 : begin
            // 'Q' get repeat count (high)
            if(tx_busy == 1'b0) begin
              tx_data_latch <= rpt_count[15:8];
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // here we consume the character.
            end
          end
          8'h58 : begin
            // 'X' read ack signal counter
            if(tx_busy == 1'b0) begin
              tx_data_latch <= {4'h3,ack_w_high};
              tx_now <= 1'b1;
              rx_byte_ready <= 1'b0;
              // character consumed
            end
          end
          default : begin
            state <= idle;
            // no change
            rx_byte_ready <= 1'b0;
            // consume the character, i.e. throw it away
          end
          endcase
          // end of case mychar
        end
        set_count_0 : begin
          // low byte of repeat count
          rx_byte_ready <= 1'b0;
          rpt_count <= {rpt_count[15:8],rx_byte_latch};
          state <= set_count_1;
        end
        set_count_1 : begin
          // high byte of repeat count
          rx_byte_ready <= 1'b0;
          rpt_count <= {rx_byte_latch,rpt_count[7:0]};
          state <= idle;
        end
        set_mode : begin
          rx_byte_ready <= 1'b0;
          // capture low 2 bits as mode
          mode <= rx_byte_latch[1:0];
          state <= idle;
        end
        wr_a0 : begin
          rx_byte_ready <= 1'b0;
          ab0 <= rx_byte_latch;
          state <= idle;
        end
        wr_a1 : begin
          rx_byte_ready <= 1'b0;
          ab1 <= rx_byte_latch;
          state <= idle;
        end
        wr_a2 : begin
          rx_byte_ready <= 1'b0;
          ab2 <= rx_byte_latch;
          state <= idle;
        end
        wr_a3 : begin
          rx_byte_ready <= 1'b0;
          ab3 <= rx_byte_latch;
          state <= idle;
        end
        wr_dat0 : begin
          return_state <= wr_dat0;
          // If there is an autoincrement repeat, come back here.
          rx_byte_ready <= 1'b0;
          wr_data_latch <= rx_byte_latch;
          state <= wr_dat1;
          ack_w_high <= 4'd0;
        end
        default : begin
          // go back to idle state - also aborts things in progress
          // Note: keeps rx_byte_ready signal active, idle state will consume it.
          // EP actually do nothing, because the state machine is handled in two parts
          // which actually sucks.
          //						state <= idle;	
          //						mem_read_rq <= '0';
          //						mem_write_rq <= '0';
        end
        endcase
      end
      // new_data = 1
      // state transitions which are not driven by data receive but by clock
      // cycles or other signals i.e memory activity
      case(state)
      wr_dat1 : begin
        mem_write_rq_state <= 1'b1;
        state <= wr_dat2;
      end
      wr_dat2 : begin
        if(mem_write_ack == 1'b1) begin
          mem_write_rq_state <= 1'b0;
          if(mode[0] == 1'b1) begin
            state <= do_auto_inc;
            // return to idle via autoinc
          end
          else begin
            state <= idle;
          end
        end
      end
      rd_dat0 : begin
        return_state <= rd_dat0;
        // If there is an autoincrement repeat, come back here.
        mem_read_rq <= 1'b1;
        state <= rd_dat1;
      end
      rd_dat1 : begin
        if(mem_read_ack == 1'b1) begin
          mem_read_rq <= 1'b0;
          state <= rd_dat2;
        end
      end
      rd_dat2 : begin
        if(tx_busy == 1'b0) begin
          tx_data_latch <= mem_data_in;
          tx_now <= 1'b1;
          if(mode[0] == 1'b1) begin
            state <= do_auto_inc;
            // return to idle via autoinc
          end
          else begin
            state <= idle;
          end
        end
      end
      do_auto_inc : begin
        // handle autoincrement.
        k = ({ab1,ab0}) + 16'd1;
        k16 = k;
        ab0 <= k16[7:0];
        ab1 <= k16[15:8];
        // hard coded repeat for reading data
        if(mode[1] == 1'b1) begin
          rpt_count <= cnt_minus1;
          if(rpt_count == 16'h0001) begin
            state <= idle;
          end
          else begin
            state <= return_state;
            // go to rd_dat0 or wr_dat0 depending on how we got here.
          end
        end
        else begin
          state <= idle;
        end
      end
      rd_count_1 : begin
        state <= rd_count_2;
        // waste 1 clock cycle, not sure how fast tx_busy goes to zero
      end
      rd_count_2 : begin
        if(tx_busy == 1'b0) begin
          // return high byte of repeat counter
          tx_data_latch <= rpt_count[15:8];
          tx_now <= 1'b1;
          state <= idle;
        end
      end
      default : begin
        // do nothing
      end
      endcase
    end
  end

  //	------------------------------
  // Clock divider: 25 000 000 / 230 400
  serial_tx #(108) uart_tx(
      .clk(clk),
    .rst(rst),
    .tx(tx),
    .block_tx(1'b0),
    .busy(uart_tx_busy),
    .data(tx_data),
    .new_data(uart_tx_now));

  serial_rx #(108) uart_receiver(
      .clk(clk),
    .rst(rst),
    .rx(rx),
    .data(uart_rx_data),
    .new_data(uart_rx_new_data));

  assign spi_tx_data = 8'h00;
  assign spi_tx_now = 1'b0;
  spi_slave spi_receiver(
      .clk(clk),
    .rst(rst),
    .cs_n(spi_cs_n),
    .spi_clk(spi_clk),
    .mosi(spi_mosi),
    .miso(spi_miso),
    .spi_rq(spi_rq),
    .rx_data(spi_rx_data),
    .rx_ready(spi_rx_ready),
    .tx_data(tx_data),
    .tx_busy(spi_tx_busy),
    .tx_new_data(spi_tx_now));


endmodule
