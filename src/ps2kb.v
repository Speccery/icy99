// PS/2 KBD interface (input only)
//
// Algorithm based on a VHDL routine by Grant Searle.
// TI-99/2 implementation and Verilog conversion by Paul Ruizendaal.
// TI-99/4A version by Erik Piehl.
// 2019 Nov
//
module PS2KBD(
  input wire clk,
  
  input wire ps2_clk,
  input wire ps2_data,
  
  output reg [7:0] ps2_code,
  output reg strobe,
  output reg err
);

  // sync ps2_data
  //
  reg serin;
  always @(posedge clk) serin <= ps2_data;
  
  // sync & 'debounce' ps2_clock
  //
  parameter LEN = 8;
  reg bitclk = 0;
  reg [LEN:0] stable = 0;

  always @(posedge clk)
  begin
    stable = { stable[LEN-1:0], ps2_clk };
    if ( &stable) bitclk <= 1;
    if (~|stable) bitclk <= 0;
  end
  
  wire bitedge = bitclk && (~|stable[LEN-1:0]);
  
  // clock in KBD bits (start - 8 data - odd parity - stop)
  //
  reg [8:0] shift = 0;
  reg [3:0] bitcnt = 0;
  reg parity = 0;

  always @(posedge clk)
  begin
    strobe <= 0; err <= 0;
    if (bitedge) begin
      // wait for start bit
      if (bitcnt==0) begin
        parity <= 0;
        if (!serin) bitcnt <= bitcnt + 1;
        end
      // shift in 9 bits (8 data + parity)
      else if (bitcnt<10) begin
        shift  <= { serin, shift[8:1] };
        parity <= parity ^ serin;
        bitcnt <= bitcnt + 1;
        end
      // check stop bit, parity
      else begin
        bitcnt <= 0;
        if (parity && serin) begin
          ps2_code <= shift[7:0];
          strobe <= 1;
          end
        else
          err <= 1;
      end
    end
  end

endmodule

// Keyboard encoder
module ps2matrix(
  input wire clk,
  input wire ps2clk, ps2data,
  input wire [2:0] line_sel,
  output reg [7:0] keyline  // 8 bits out
);

  wire [7:0] code;
  wire strobe;
  PS2KBD kdb(clk, ps2clk, ps2data, code, strobe, );

  reg [7:0] matrix[0:7];
  reg extended = 0, action = 0;

  initial begin
    matrix[0] = 8'hff; matrix[1] = 8'hff; 
    matrix[2] = 8'hff; matrix[3] = 8'hff; 
    matrix[4] = 8'hff; matrix[5] = 8'hff;
    matrix[6] = 8'hff; matrix[7] = 8'hff;
  end

  // Debug outputs
  //
  reg special = 0;
  wire shifted = !matrix[0][5]; // !matrix[4][7] | !matrix[5][1];

  // Read out KBD matrix
  //
  always @(posedge clk)
  begin
    keyline <= matrix[line_sel];
  end

  // Convert PS/2 scan codes into TI99/4 KBD matrix state
  //
  reg [7:0] decode;

  always @(posedge clk)
  begin
    if (strobe) begin
      if (code==8'he0)
        extended <= 1;
      else if (code==8'hf0)
        action <= 1; // up
      else begin
        extended <= 0;
        action <= 0; // down

/* Convenient key remaps:
  shift-/ => fctn-i (?)
  shift-- => fctn-u (_)
  [       => fctn-r
  ]       => fctn-t
  shift-[ => fctn-f
  shift-] => fctn-g
  \       => fctn-z
  `       => fctn-c
  shift-` => fctn-w (~)
  up      => fctn-e
  left    => fctn-s
  right   => fctn-d
  down    => fctn-x
*/
        // Convenience mappings
        decode = code;
        special <= !action;
/*        
        if (!shifted) begin
            case (code)
            8'h4e: decode = 8'h4a; // - -> shift-/
            8'h52: decode = 8'h44; // ' -> shift-O
            default: special <= 0;
          endcase
          end
        else begin
          case (code)
            // 8'h4a: decode = 8'h43; // ? -> shift-I
            8'h52: decode = 8'h4d; // " -> shift-P
            default: special <= 0;
          endcase
        end
*/
        case (decode)
          8'h16: matrix[5][4] <= action; // 1
          8'h1e: matrix[1][4] <= action; // 2
          8'h26: matrix[2][4] <= action; // 3
          8'h25: matrix[3][4] <= action; // 4
          8'h2e: matrix[4][4] <= action; // 5			
          8'h36: matrix[4][3] <= action; // 6
          8'h3d: matrix[3][3] <= action; // 7
          8'h3e: matrix[2][3] <= action; // 8
          8'h46: matrix[1][3] <= action; // 9
          8'h45: matrix[5][3] <= action; // 0
          8'h4e: matrix[5][0] <= action; // / duplicate
          8'h55: matrix[0][0] <= action; // =
          // Backspace:
          8'h66: begin
            matrix[0][4] <= action;  // FCTN
            matrix[1][5] <= action;  // S
          end 
          // Left arrow E0 6B
          8'h6b: begin
              if (extended) begin
                matrix[0][4] <= action;  // FCTN
                matrix[1][5] <= action;  // S

                matrix[6][1] <= action;   // Joystick 1 left
              end
          end
          // Right arrow E0 74
          8'h74: begin
              if (extended) begin
                matrix[0][4] <= action;  // FCTN
                matrix[2][5] <= action;  // D

                matrix[6][2] <= action;   // Joystick 1 right
              end
          end
          // Up arrow E0 75
          8'h75: begin
              if (extended) begin
                matrix[0][4] <= action;  // FCTN
                matrix[2][6] <= action;  // E

                matrix[6][4] <= action;   // Joystick 1 up
              end
          end
          // Down arrow E0 72
          8'h72: begin
              if (extended) begin
                matrix[0][4] <= action;  // FCTN
                matrix[1][7] <= action;  // X

                matrix[6][3] <= action;   // Joystick 1 down
              end
          end
          // Delete E0 71
          8'h71: begin
              if (extended) begin
                matrix[0][4] <= action;  // FCTN
                matrix[5][4] <= action;  // 1
              end
          end

      //  8'h0d: // TAB
          8'h15: matrix[5][6] <= action; // Q
          8'h1d: matrix[1][6] <= action; // W
          8'h24: matrix[2][6] <= action; // E
          8'h2d: matrix[3][6] <= action; // R
          8'h2c: matrix[4][6] <= action; // T				
          8'h35: matrix[4][2] <= action; // Y
          8'h3c: matrix[3][2] <= action; // U
          8'h43: matrix[2][2] <= action; // I
          8'h44: matrix[1][2] <= action; // O
          8'h4d: matrix[5][2] <= action; // P
      //  8'h54: // [
      //  8'h5b: // ]
      //  8'h0e: // Backslash

      //  8'h58: // Caps lock
          8'h1c: matrix[5][5] <= action; // A
          8'h1b: matrix[1][5] <= action; // S
          8'h23: matrix[2][5] <= action; // D
          8'h2b: matrix[3][5] <= action; // F
          8'h34: matrix[4][5] <= action; // G
          8'h33: matrix[4][1] <= action; // H
          8'h3b: matrix[3][1] <= action; // J
          8'h42: matrix[2][1] <= action; // K
          8'h4b: matrix[1][1] <= action; // L
          8'h4c: matrix[5][1] <= action; // ;
      //  8'h52: // '
          8'h5a: matrix[0][2] <= action; // ENTER

          8'h12: matrix[0][5] <= action; // L-SHIFT
          8'h1a: matrix[5][7] <= action; // Z
          8'h22: matrix[1][7] <= action; // X
          8'h21: matrix[2][7] <= action; // C
          8'h2a: matrix[3][7] <= action; // V
          8'h32: matrix[4][7] <= action; // B
          8'h31: matrix[4][0] <= action; // N
          8'h3a: matrix[3][0] <= action; // M
          8'h41: matrix[2][0] <= action; // ,
          8'h49: matrix[1][0] <= action; // .
          8'h4a: matrix[5][0] <= action; // /
          8'h59: matrix[0][5] <= action; // R-SHIFT

          // 8'h76: matrix[5][7] <= action; // ESC = BREAK
          8'h29: matrix[0][1] <= action; // SPACE
          8'h14: begin
            matrix[0][6] <= action; // CTRL
            if(extended) 
              matrix[6][0] <= action; // Right control is joystick 1 fire
          end
          8'h11: matrix[0][4] <= action; // L-ALT = FCTN
        endcase
      end
    end
  end

endmodule
