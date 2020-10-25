//
// TMS9902 component
//
// Datasheet available at
// http://ftp.whtech.com/datasheets%20and%20manuals/Datasheets%20-%20TI/TMS9902A.pdf 
//
// This source code is public domain.
//

module tms9902 (CLK, nRTS, nDSR, nCTS, nINT, nCE, CRUOUT, CRUIN, CRUCLK, XOUT, RIN, S);

  output nRTS, nINT, CRUIN, XOUT;
  input  CLK, nDSR, nCTS, nCE, CRUOUT, CRUCLK, RIN;
  input  [4:0] S;

  wire   nRTS, XOUT, nINT, CRUIN;
  wire   CLK, nDSR, nCTS, nCE, CRUOUT, CRUCLK, RIN;
  wire   [4:0] S;

  // Synchronise RIN
  reg srin;
  always @(posedge CLK) srin = RIN;
  
  // ==========================================================================
  // CLOCK DIVIDER
  // ==========================================================================

  `define MHz 25
  reg    [5:0] clkctr_q = 0, clkctr_d;
  wire   bitclk;
  
  assign bitclk = (clkctr_q==0);
  
  always @(posedge CLK) clkctr_q = clkctr_d;
  
  always @(clkctr_q)
  begin : clkctr_cmb
    if (clkctr_q==0)
      clkctr_d = `MHz - 1;
    else    
      clkctr_d = clkctr_q - 1;
  end

  // ==========================================================================
  // CRU FLAGS + CONTROLLER
  // ==========================================================================

  `define reset    31

  `define cruclk   25
  `define dsch     24
  `define pdsr     23
  `define pcts     22
  
  `define dscenb   21
  `define timenb   20
  `define xienb    19
  `define rienb    18
  `define brkon    17
  `define rtson    16
  `define tstmd    15
  `define ldctl    14
  `define ldir     13
  `define lrdr     12
  `define lxdr     11

  `define sbs     7:6
  `define penb      5
  `define podd      4
  `define clk4m     3
  `define rcl     1:0

  wire   sig_wrsel    = nCE==0 && CRUCLK==1;
  
  // S address decoder
  //
  wire   sig_crudata  = (S<11)       && sig_wrsel;
  wire   sig_crudata7 = sig_crudata && !S[3];
  wire   sig_cructl   = (S<22)       && sig_wrsel;
  wire   sig_reset    = (S==`reset)  && sig_wrsel;
  wire   sig_timenb   = (S==`timenb) && sig_wrsel;
  wire   sig_rienb    = (S==`rienb)  && sig_wrsel;
  wire   sig_dscenb   = (S==`dscenb) && sig_wrsel;

  wire   sig_ldir     = (cruFLG_q[`ldir] && !cruFLG_d[`ldir]) || sig_timenb;
  
  // Flag & control register
  //
  reg    [25:0] cruFLG_q, cruFLG_d;
  
  always @(posedge CLK) cruFLG_q = cruFLG_d;
  
  always @(cruFLG_q, sig_reset, sig_cructl, sig_dscenb, ndsr2, ncts2, CRUCLK, S)
  begin : cruFLG_cmb
    
    cruFLG_d = cruFLG_q;
  
    // process flag & control bits
    if (sig_reset)
      begin
        cruFLG_d = 0;
        cruFLG_d[`ldctl:`lxdr] = 4'b1111;
      end
    else if (sig_cructl && ~sig_crudata)
      cruFLG_d[S] = CRUOUT;
    else if (sig_crudata && ~S[3] && cruFLG_q[`ldctl]) // bits 7:0 only
      cruFLG_d[S] = CRUOUT;
    
    if (sig_dscenb)
      cruFLG_d[`dsch] = 0;
    
    // monitor and flag device state change bits
    cruFLG_d[`pdsr] = ndsr2;
    cruFLG_d[`pcts] = ncts2;
    if (cruFLG_q[`pdsr]!=ndsr2 || cruFLG_q[`pcts]!=ncts2)
      cruFLG_d[`dsch] = 1;

    // On falling edge of CRUCLK reset register select bits as needed
    cruFLG_d[`cruclk] = CRUCLK;
    if (cruFLG_q[`cruclk] && ~CRUCLK)
    begin
      if ((S==10) && ~cruFLG_q[`ldctl] && ~cruFLG_q[`ldir] && cruFLG_q[`lrdr])
        cruFLG_d[`lrdr] = 0;
      else if (S==7)
        if (cruFLG_q[`ldctl])
          cruFLG_d[`ldctl] = 0;
        else
          cruFLG_d[`ldir]  = 0;
    end
  end

  // prepare half-bit times for data bits and stop bits
  //
  reg [4:0] xbits, sbits;
  
  always @(cruFLG_q)
  begin
    case (cruFLG_q[`rcl])
      2'd3: xbits = 16;
      2'd2: xbits = 14;
      2'd1: xbits = 12;
      2'd0: xbits = 10;
    endcase
    case (cruFLG_q[`sbs])
      2'b00:   sbits = 3;
      2'b01:   sbits = 4;
      default: sbits = 2;
    endcase
  end
  
  // Implement TSTMD functionality
  //
  wire   ncts2 = (cruFLG_q[`tstmd]!=1) ? nCTS : nRTS;
  wire   rin2  = (cruFLG_q[`tstmd]!=1) ? srin : XOUT;
  wire   ndsr2 = (cruFLG_q[`tstmd]!=1) ? nDSR : 0;

  // ==========================================================================
  // INTERVAL TIMER
  // ==========================================================================

  // Timer register
  //
  reg    [7:0] timreg_q, timreg_d;       // timer interval register

  always @(posedge CLK) timreg_q = timreg_d;
  
  always @(sig_crudata or S)
  begin : tmr_cmb
    timreg_d = timreg_q;
    if (sig_crudata7 && !cruFLG_q[`ldctl] && cruFLG_q[`ldir])
      timreg_d[S] = CRUOUT;
  end

  // Timer counter
  //
  reg    [7:0] timctr_q, timctr_d; // timer counter register
  wire   sig_tim_ctr_iszero;

  always @(posedge CLK) timctr_q = timctr_d;
  
  assign sig_tim_ctr_iszero = (timctr_q==0) && bitclk;
  
  always @(bitclk or timctr_q or sig_tim_ctr_iszero or cruFLG_q[`tstmd])
  begin : timctr_cmb
    timctr_d = timctr_q;
    if (sig_ldir || sig_tim_ctr_iszero)
       timctr_d = {timreg_q, 6'b000000};
    else if (bitclk)
       timctr_d = timctr_q - ((cruFLG_q[`tstmd]) ? 32 : 1);
  end

  // Timer controller
  //
  `define timelp 0
  `define timerr 1
  reg    [1:0] timFSM_q, timFSM_d; // timer control register

  always @(posedge CLK) timFSM_q = timFSM_d;
  
  always @(sig_reset or sig_timenb or sig_tim_ctr_iszero)
  begin : timFSM_cmb
    timFSM_d = timFSM_q;
    if (sig_reset || sig_timenb) begin
      timFSM_d[`timelp] = 0;
      timFSM_d[`timerr] = 0;
    end else if (sig_tim_ctr_iszero) begin
      if (timFSM_q[`timelp]) timFSM_d[`timerr] = 1;
      timFSM_d[`timelp] = 1;
    end
  end

  // ==========================================================================
  //   TRANSMITTER
  // ==========================================================================
  
  reg sig_xhb_reset;
  reg sig_xbr7;
  reg sig_xsr_load;
  reg sig_xsr_shift;
  
  // Transmit data rate register
  //
  reg [10:0] xdr_q, xdr_d;
  
  always @(posedge CLK) xdr_q = xdr_d;
  
  always @(xdr_q, cruFLG_q, sig_reset, S, CRUOUT)
  begin : xdr_cmb
    xdr_d = xdr_q;
    if (sig_reset)
      xdr_d = 0;
    else if (sig_crudata && !cruFLG_q[`ldctl] && !cruFLG_q[`ldir] && cruFLG_q[`lxdr])
      xdr_d[S] = CRUOUT;
  end

  // Transmit buffer register
  //
  reg [7:0] xbr_q, xbr_d;
  
  always @(posedge CLK) xbr_q = xbr_d;
  
  always @(xbr_q, sig_crudata7, cruFLG_q, S, CRUOUT)
  begin : xbr_cmb
    xbr_d = xbr_q;
    sig_xbr7 = 0;
    if (sig_crudata7 && !cruFLG_q[`ldctl] && !cruFLG_q[`ldir] && !cruFLG_q[`lrdr] && !cruFLG_q[`lxdr])
    begin
      xbr_d[S] = CRUOUT;
      sig_xbr7 = (S==7);
    end
  end
  
  // Transmit shift register
  //
  reg [7:0] xsr_q, xsr_d;
  
  always @(posedge CLK) xsr_q = xsr_d;
  
  always @(xsr_q, xbr_q, sig_xsr_load, sig_xsr_shift)
  begin : xsr_cmb
    xsr_d = xsr_q;
    if (sig_xsr_load)
      xsr_d = xbr_q;
    else if (sig_xsr_shift)
      xsr_d = {1'b0, xsr_q[7:1]};
  end

  // Transmit half-bit counter register
  //
  reg [12:0] xhbctr_q, xhbctr_d;

  always @(posedge CLK) xhbctr_q = xhbctr_d;

  wire sig_xhbctr_iszero = (xhbctr_q == 13'd0);

  always @(xhbctr_q, xdr_q, bitclk, sig_xhb_reset, sig_xhbctr_iszero)
  begin : xhbctr_cmb
    xhbctr_d = xhbctr_q;
    if (sig_xhb_reset || sig_xhbctr_iszero)
      xhbctr_d = {xdr_q[9:0], 3'b000};
    else if (bitclk)
      xhbctr_d = xhbctr_q - (!xdr_q[10] ? 8 : 1);
  end

  // Transmit controller and FSM
  //
  `define bitctr 4:0
  `define state 7:5
  `define xbre   8
  `define xsre   9
  `define xout   10
  `define rts    11
  `define par    12

  wire rtson = (cruFLG_q[`rtson] && !ncts2);
  
  // Transmitter FSM states
  parameter IDLE = 3'd0, BREAK = 3'd1, START = 3'd2, BITS = 3'd3, PARITY = 3'd4, STOP = 3'd5;

  reg [12:0] xmtFSM_q, xmtFSM_d;
  
  always @(posedge CLK) xmtFSM_q = xmtFSM_d;

  always @(xmtFSM_q, cruFLG_q, xsr_q, ncts2, sig_xbr7, sig_reset, sig_xhbctr_iszero)
  begin : xmtFSM_cmb

    xmtFSM_d = xmtFSM_q;
    sig_xhb_reset = 0; sig_xsr_load = 0; sig_xsr_shift = 0;

    if (sig_xhbctr_iszero)
      xmtFSM_d[`bitctr] = xmtFSM_q[`bitctr] - 1;
      
    if (sig_reset)
    begin
      xmtFSM_d = 13'b00111_000_00000;
      sig_xhb_reset = 1;
    end

    else if (sig_xbr7)
      xmtFSM_d[`xbre] = 0;
      
    else if (xmtFSM_d[`state]==BREAK)
    begin
      xmtFSM_d[`xout] = 0;
      if (!cruFLG_q[`brkon]) xmtFSM_d[`state] = IDLE;
    end
    
    else if (xmtFSM_d[`state]==IDLE)
      begin
        xmtFSM_d[`rts] = cruFLG_q[`rtson];
        if (cruFLG_q[`rtson] && !ncts2)
        begin
          if (xmtFSM_d[`xbre])
            begin
            if (cruFLG_q[`brkon])  xmtFSM_d[`state] = BREAK;
            end
          else
            begin
            xmtFSM_d[`state]  = START;
            xmtFSM_d[`xout]   = 0;
            xmtFSM_d[`bitctr] = 5'd2;
            sig_xhb_reset     = 1;
            end
        end
      end

    else if (sig_xhbctr_iszero)
      case (xmtFSM_d[`state])
      
      START:
        if (xmtFSM_d[`bitctr]==0)
        begin
          sig_xsr_load = 1;
          xmtFSM_d[`xsre]   = 0;
          xmtFSM_d[`xbre]   = 1;
          xmtFSM_d[`state]  = BITS;
          xmtFSM_d[`bitctr] = xbits;
          xmtFSM_d[`par]    = 0;
        end

      BITS:
        begin
          if (!xmtFSM_d[0])
          begin
            xmtFSM_d[`par] = xmtFSM_q[`par] ^ xsr_q[0];
            sig_xsr_shift = 1;
          end
          if (xmtFSM_q[`bitctr]==0)
            if (cruFLG_q[`penb])
            begin
              xmtFSM_d[`xout]   = xmtFSM_q[`par] ^ cruFLG_q[`podd];
              xmtFSM_d[`state]  = PARITY;
              xmtFSM_d[`bitctr] = 5'd2;
            end
            else begin
              xmtFSM_d[`xout]   = 1;
              xmtFSM_d[`state]  = STOP;
              xmtFSM_d[`bitctr] = sbits;
            end
        end

      PARITY:
        if (xmtFSM_d[`bitctr]==0)
        begin
          xmtFSM_d[`xout]   = 1;
          xmtFSM_d[`state]  = STOP;
          xmtFSM_d[`bitctr] = sbits;
        end

      STOP:
        if (xmtFSM_d[`bitctr]==0)
        begin
          xmtFSM_d[`xsre]  = 1;
          xmtFSM_d[`state] = IDLE;        
        end
      
      default:
        xmtFSM_d[`state] = IDLE;

      endcase

  end
  
  assign XOUT = xmtFSM_q[`state]==BITS ? xsr_q[0] : xmtFSM_q[`xout];
  assign nRTS = ~xmtFSM_q[`rts];

  // ==========================================================================
  //   RECEIVER
  // ==========================================================================
  
  reg sig_rbr_load;
  reg sig_rsr_shift;
  reg sig_rhb_reset;
  
  // Receive data rate register
  //
  reg [10:0] rdr_q, rdr_d;
  
  always @(posedge CLK) rdr_q = rdr_d;
  
  always @(rdr_q, cruFLG_q, sig_reset, S, CRUOUT)
  begin : rdr_cmb
    rdr_d = rdr_q;
    if (sig_reset)
      rdr_d = 0;
    else if (sig_crudata && !cruFLG_q[`ldctl] && !cruFLG_q[`ldir] && cruFLG_q[`lrdr])
      rdr_d[S] = CRUOUT;
  end

  // Receive buffer register
  //
  reg [7:0] rbr_q, rbr_d;
  
  always @(posedge CLK) rbr_q = rbr_d;
  
  always @(rbr_q, sig_rbr_load, cruFLG_q, S, CRUOUT)
  begin : rbr_cmb
    rbr_d = rbr_q;
    if (sig_rbr_load)
    begin
      case (cruFLG_q[`rcl])
      2'd3: rbr_d = rsr_q;
      2'd2: rbr_d = { 1'b0,   rsr_q[7:1] };
      2'd1: rbr_d = { 2'b00,  rsr_q[7:2] };
      2'd0: rbr_d = { 3'b000, rsr_q[7:3] };
      endcase
    end
  end

  // Recieve shift register
  //
  reg [7:0] rsr_q, rsr_d;
  
  always @(posedge CLK) rsr_q = rsr_d;
  
  always @(xsr_q, rbr_q, rin2, sig_rsr_shift)
  begin : rsr_cmb
    rsr_d = rsr_q;
    if (sig_rsr_shift)
      rsr_d = {rin2, rsr_q[7:1]};
  end
 
  // Receive half-bit counter register
  //
  reg [12:0] rhbctr_q, rhbctr_d;

  always @(posedge CLK) rhbctr_q = rhbctr_d;

  wire sig_rhbctr_iszero = (rhbctr_q == 13'd0);

  always @(rhbctr_q, rdr_q, bitclk, sig_rhb_reset, sig_rhbctr_iszero)
  begin : rhbctr_cmb
    rhbctr_d = rhbctr_q;
    if (sig_rhb_reset || sig_rhbctr_iszero)
      rhbctr_d = {rdr_q[9:0], 3'b000};
    else if (bitclk)
      rhbctr_d = rhbctr_q - (!rdr_q[10] ? 8 : 1);
  end

  // Receive controller and FSM
  //
  // bits 0:7 are bitctr and state
  `define rbrl   8
  `define rsbd   9
  `define rfbd   10
  `define rover  11
  `define rper   12
  `define rfer   13
  `define par    14
  
  // Receive FSM state START1 replaces BREAK from the transmit state numbers
  parameter START1 = 3'd1;
  
  reg [14:0] rcvFSM_q, rcvFSM_d;
  
  always @(posedge CLK) rcvFSM_q = rcvFSM_d;

  always @(rcvFSM_q, cruFLG_q, rin2, sig_reset, sig_rienb, sig_rhbctr_iszero)
  begin : rcvFSM_cmb
  
    rcvFSM_d = rcvFSM_q;
    sig_rhb_reset = 0; sig_rbr_load = 0; sig_rsr_shift = 0;

    if (sig_rhbctr_iszero)
      rcvFSM_d[`bitctr] = rcvFSM_q[`bitctr] - 1;

    if (sig_reset || sig_rienb)
    begin
      rcvFSM_d = 0;
      sig_rhb_reset = 1;
    end

    if (rcvFSM_d[`state]==IDLE)
    begin
      rcvFSM_d[`rsbd] = 0;
      rcvFSM_d[`rfbd] = 0;
      if (rin2)
        rcvFSM_d[`state] = START1;
    end

    else if (rcvFSM_d[`state]==START1)
    begin
      if (!rin2)
      begin
        rcvFSM_d[`state]  = START;
        rcvFSM_d[`bitctr] = 1;
        sig_rhb_reset = 1;
      end
    end

    else if (sig_rhbctr_iszero)
      case (rcvFSM_d[`state])

      START:
        if (rcvFSM_d[`bitctr]==0)
          if (rin2)
            rcvFSM_d[`state] = IDLE;
          else
          begin
            rcvFSM_d[`state]  = BITS;
            rcvFSM_d[`bitctr] = xbits;
            rcvFSM_d[`par]    = 0;
            rcvFSM_d[`rsbd]   = 1;
          end

      BITS:
        begin
          if (!rcvFSM_d[0]) // at half bit time, read bit
          begin
            rcvFSM_d[`par]  = rcvFSM_d[`par] ^ rin2;
            rcvFSM_d[`rfbd] = 1;
            sig_rsr_shift = 1;
          end;
          if (rcvFSM_d[`bitctr]==0)
          begin
            rcvFSM_d[`bitctr] = 2;
            if (cruFLG_q[`penb])
              rcvFSM_d[`state] = PARITY;
            else
              rcvFSM_d[`state] = STOP;
          end
        end

      PARITY:
        if (rcvFSM_d[`bitctr]==0)
        begin
          rcvFSM_d[`par]    = rcvFSM_d[`par] ^ rin2;
          rcvFSM_d[`state]  = STOP;
          rcvFSM_d[`bitctr] = 2;
        end

      STOP:
        if (rcvFSM_d[`bitctr]==0)
        begin
          rcvFSM_d[`rover]  = rcvFSM_d[`rbrl];
          rcvFSM_d[`rper]   = rcvFSM_d[`par];
          rcvFSM_d[`rfer]   = !rin2;
          rcvFSM_d[`rbrl]   = 1;
          rcvFSM_d[`state]  = IDLE;
          sig_rbr_load = 1;
        end

      default:
        rcvFSM_d[`state]  = IDLE;

      endcase
  end

  // ==========================================================================
  //   CRU INPUT
  // ==========================================================================
  
  //    Combinational helper signals (see figure 7 datasheet)
  //
  wire dscint = cruFLG_q[`dsch]   & cruFLG_q[`dscenb];
  wire rint   = rcvFSM_q[`rbrl]   & cruFLG_q[`rienb];
  wire xint   = xmtFSM_q[`xbre]   & cruFLG_q[`xienb];
  wire timint = timFSM_q[`timelp] & cruFLG_q[`timenb];
  wire intr   = dscint | rint | xint | timint;

  assign nINT  = !intr;

  wire rcverr = rcvFSM_q[`rfer] | rcvFSM_q[`rover] | rcvFSM_q[`rper];
  wire flag   = cruFLG_q[`ldctl] | cruFLG_q[`ldir] | cruFLG_q[`lrdr] |
                cruFLG_q[`lxdr] | cruFLG_q[`brkon];
  
  // the CRUIN signal is essentially a 32-way mux with a tri-state output
  //
  reg cruin;

  always @(S, intr, flag, cruFLG_q, nCTS, nDSR, nRTS, timFSM_q, dscint,
           timint, xint, rint, RIN, rcvFSM_q, rbr_q)
  begin
    case (S)
    31: cruin = intr;              // any interupt pending
    30: cruin = flag;              // 'flag' field
    29: cruin = cruFLG_q[`dsch];   // device status change
    28: cruin = !nCTS;             // inverse nCTS input
    27: cruin = !nDSR;             // inverse nDSR input
    26: cruin = !nRTS;             // inverse nRTS output
    25: cruin = timFSM_q[`timelp]; // timer elapsed
    24: cruin = timFSM_q[`timerr]; // timer elapsed more than once
    23: cruin = xmtFSM_q[`xsre];   // transmit shift register empty
    22: cruin = xmtFSM_q[`xbre];   // transmit buffer register empty
    21: cruin = rcvFSM_q[`rbrl];   // receiver buffer register loaded
    20: cruin = dscint;            // device status change interrupt pending
    19: cruin = timint;            // timer interrupt pending
    18: cruin = 0;                 // not used (always 0)
    17: cruin = xint;              // transmit interrupt pending
    16: cruin = rint;              // receiver interrupt pending
    15: cruin = RIN;               // copy of RIN input
    14: cruin = rcvFSM_q[`rsbd];   // receive start bit detected
    13: cruin = rcvFSM_q[`rfbd];   // receive fisrt bit detected
    12: cruin = rcvFSM_q[`rfer];   // receive framing error
    11: cruin = rcvFSM_q[`rover];  // receive overflow error
    10: cruin = rcvFSM_q[`rper];   // receive parity error
     9: cruin = rcverr;            // any receive error
     8: cruin = 0;                 // not used (always 0)
    default: cruin = rbr_q[S];     // receiver buffer register[7:0]
    endcase
  end
  
//  assign CRUIN = nCE ? 1'bz : cruin;
  assign CRUIN = nCE ? 1'b0 : cruin;

endmodule //tms9902
