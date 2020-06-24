//
// xmemctrl.vhd
//
// External memory controller for the EP994A design.
// Erik Piehl (C) 2019-03-14
// The idea is to package in this module the state machines etc
// to drive external memory, be that SRAM or SDRAM.
// no timescale needed

module xmemctrl(
  input wire clock,
  input wire reset,   // active high
  // SRAM signals
  output reg  [15:0] SRAM_DAT_out,
  input  wire [15:0] SRAM_DAT_in,
  output wire SRAM_DAT_drive,
  output wire [17:0] SRAM_ADR,
  output wire SRAM_CE,
  output wire SRAM_WE,
  output wire SRAM_OE,
  output reg [1:0] SRAM_BE,

  // CPU address bus for external memory
  input wire [18:0] xaddr_bus,

  // Flash memory loading (from serial flash)
  input wire [15:0] flashDataOut,
  input wire [17:0] flashAddrOut,
  input wire flashLoading,
  input wire flashRamWE_n,

  // CPU signals
  input wire cpu_holda,
  input wire MEM_n,
  input wire [15:0] data_from_cpu,
  output wire [15:0] read_bus_o,
  input wire cpu_wr_rq, // CPU write request
  input wire cpu_rd_rq, // CPU read request
  output reg cpu_wr_ack,
  output reg cpu_rd_ack,

  // memory controller (serloader) signals
  input wire [7:0] mem_data_out,
  output reg [7:0] mem_data_in,
  input wire [31:0] mem_addr,
  input wire mem_read_rq,
  input wire mem_write_rq,
  output wire mem_read_ack_o,
  output wire mem_write_ack_o,

  // memory controller signals for VDP
  input wire [13:0] vdp_addr,
  output reg  [7:0] vdp_data_out,
  input  wire [7:0] vdp_data_in,
  input  wire vdp_read_rq,   
  output reg  vdp_read_ack, 
  input  wire vdp_pipeline_reads,
  input  wire vdp_write_rq,  
  output reg  vdp_write_ack
);

// SRAM memory controller state machine
parameter [3:0]
  idle = 0,
  wr0 = 1,
  wr1 = 2,
  wr2 = 3,
  rd0 = 4,
  rd1 = 5,
  rd2 = 6,
  grace = 7,
  cpu_wr2 = 8,
  cpu_rd2 = 9,
  vdp_rd0 = 10,
  vdp_wr0 = 11,
  vdp_wr1 = 12,
  cpu_pre_wr2 = 13;

reg [3:0] mem_state = idle;
reg mem_drive_bus = 1'b0; // High when external memory controller is driving bus
reg ram_cs_n;
reg sram_we_n;
reg sram_oe_n;
reg cpu_mem_write_pending;
reg cpu_mem_read_pending;
reg [1:0] accessor;  // 00 VDP, 01 CPU, 10 flashloader, 11 mem ctrl/serloader
parameter [1:0] access_vdp=0, access_cpu=1, access_flash_ldr=2, access_mem_serloader=3;
reg lastFlashRamWE_n;
reg mem_read_ack;
reg mem_write_ack;
reg [17:0] addr;
reg [15:0] data_read_for_cpu;
reg vdp_write_pending;
reg vdp_read_pending;
reg vdp_last_addr0; // For pipelining, it is necessary to remember the LSB of address to select correct byte of 16-bit word
reg vdp_first_pipelined_read;

  assign SRAM_ADR = addr;
  
  // Static RAM databus driving
  // assign SRAM_DAT_out = 
  //     accessor == access_flash_ldr     && mem_drive_bus == 1'b1 ? flashDataOut :  // Flash memory loading
  //     accessor == access_mem_serloader && mem_drive_bus == 1'b1 ? { mem_data_out,mem_data_out } :          // Memory controller
  //     accessor == access_vdp           && mem_drive_bus == 1'b1 ? { vdp_data_in, vdp_data_in } : // VDP
  //     data_from_cpu;

  assign SRAM_DAT_drive = (accessor == access_flash_ldr && mem_drive_bus == 1'b1)
                       || (accessor == access_mem_serloader && mem_drive_bus == 1'b1)
                       || (accessor == access_vdp && mem_drive_bus == 1'b1)
                       || (accessor == access_cpu && (mem_state == cpu_wr2 || mem_state == cpu_pre_wr2));

  assign read_bus_o = data_read_for_cpu; // read_bus;
  assign SRAM_CE = ram_cs_n;
  assign SRAM_WE = sram_we_n;
  assign SRAM_OE = sram_oe_n;
  
  // CPU owns the bus except when in hold
  assign mem_read_ack_o = mem_read_ack;
  assign mem_write_ack_o = mem_write_ack;
  always @(posedge clock) begin
    if(reset == 1'b1) begin
      mem_state <= idle;
      mem_drive_bus <= 1'b0;
      ram_cs_n <= 1'b1;
      sram_we_n <= 1'b1;
      sram_oe_n <= 1'b1;
      cpu_mem_write_pending <= 1'b0;
      cpu_mem_read_pending <= 1'b0;
      vdp_read_pending <= 1'b0;
      vdp_write_pending <= 1'b0;
    end
    else begin
      // for flash loading, sample the status of flashRamWE_n
      lastFlashRamWE_n <= flashRamWE_n;
      if(cpu_wr_rq == 1'b1 && MEM_n == 1'b0) begin
        cpu_mem_write_pending <= 1'b1;
      end

      if(cpu_rd_rq == 1'b1 && MEM_n == 1'b0) begin
        cpu_mem_read_pending <= 1'b1;
      end

      if(vdp_read_rq)
        vdp_read_pending <= 1'b1;
      if(vdp_write_rq)
        vdp_write_pending <= 1'b1;

      // The acks are high only for one cycle each
      mem_read_ack <= 1'b0;
      mem_write_ack <= 1'b0;
      vdp_read_ack  <= 1'b0;
      vdp_write_ack <= 1'b0;
      cpu_wr_ack <= 1'b0;
      cpu_rd_ack <= 1'b0;
      // memory controller state machine
      case(mem_state)
      idle : begin
        mem_drive_bus <= 1'b0;
        ram_cs_n <= 1'b1;
        sram_we_n <= 1'b1;
        sram_oe_n <= 1'b1;
        // addr <= xaddr_bus;
        if(vdp_read_rq || vdp_read_pending) begin
          // SRAM addresses are 18 bits, and address 16-bit words, so 19 bits for byte accesses.
          // VDP addresses are 14 bits for byte accesses. For now set VDP RAM to 4000..7FFF in CPU RAM.
          // In word addresses this is 2000..3FFF, i.e. 000_001v_vvvv_vvvv_vvvv
          vdp_read_pending <= 1'b0;
          vdp_last_addr0 <= vdp_addr[0];
          addr <= { 5'b01000, vdp_addr[13:1]};  // VRAM at 128K
          accessor <= access_vdp;
          ram_cs_n <= 1'b0;                 // init read cycle
          sram_oe_n <= 1'b0;
          mem_drive_bus <= 1'b0;
          mem_state <= vdp_rd0;
          vdp_first_pipelined_read <= 1'b1; // If this is a pipelined read, only ack the first.
          // SRAM byte enables. These are active low. Big endian, so for 
          // byte addresses addr[0]=0 is data[15:8] and addr[0]=1 is data[7:0].
          SRAM_BE <= { vdp_addr[0], ~vdp_addr[0] };
        end else if (vdp_write_rq || vdp_write_pending) begin
          vdp_write_pending <= 1'b0;
          addr <= { 5'b01000, vdp_addr[13:1]};  // VRAM at 128K
          vdp_last_addr0 <= vdp_addr[0];        // Writes are not pipelined, but this controls byte enables
          accessor <= access_vdp;
          SRAM_DAT_out <= { vdp_data_in, vdp_data_in };
          ram_cs_n <= 1'b0;                 // initiate write cycle
          // delayed the issue of write strobe: sram_we_n <= 1'b0;
          mem_drive_bus <= 1'b1;            // only writes drive the bus   (for non-CPU writes)
          mem_state <= vdp_wr0;
          SRAM_BE <= { vdp_addr[0], ~vdp_addr[0] };
        end else 
        if(flashLoading == 1'b1 && cpu_holda == 1'b1 && flashRamWE_n == 1'b0 && lastFlashRamWE_n == 1'b1) begin
          // We are loading from flash memory chip to SRAM.
          // For this ICE40HX version I am not sure if this will be used. Only support writing to the low 256K.
          // Note that addresses from flashAddrOut are byte address but LSB set to zero
          addr <= { 1'b0, flashAddrOut[17:1]};  // 256K range from 00000
          mem_state <= wr0;
          mem_drive_bus <= 1'b1;    // only writes drive the bus (for non-CPU writes)
          accessor <= access_flash_ldr;
          SRAM_DAT_out <= flashDataOut;
          SRAM_BE <= 2'b00;
        end 
        else if(mem_write_rq == 1'b1 && mem_addr[20] == 1'b0 && cpu_holda == 1'b1) begin
          // normal memory write by memory controller circuit
          addr <= mem_addr[18:1]; // setup address
          mem_state <= wr0;
          mem_drive_bus <= 1'b1;  // only writes drive the bus
          accessor <= access_mem_serloader;
          SRAM_DAT_out <= { mem_data_out,mem_data_out };
          SRAM_BE <= { mem_addr[0], ~mem_addr[0] };
        end
        else if(mem_read_rq == 1'b1 && mem_addr[20] == 1'b0 && cpu_holda == 1'b1) begin
          addr <= mem_addr[18:1];           // setup address
          mem_state <= rd0;
          mem_drive_bus <= 1'b0;
          accessor <= access_mem_serloader;
          SRAM_BE <= { mem_addr[0], ~mem_addr[0] };
        end
        else if((cpu_rd_rq == 1'b1 && MEM_n == 1'b0) || cpu_mem_read_pending == 1'b1) begin
          // init CPU read cycle
          addr <= xaddr_bus;
          mem_state <= cpu_rd2;
          ram_cs_n <= 1'b0;                 // init read cycle
          sram_oe_n <= 1'b0;
          mem_drive_bus <= 1'b0;
          cpu_mem_read_pending <= 1'b0;
          accessor <= access_cpu;
          SRAM_BE <= 2'b00;
        end
        else if((cpu_wr_rq == 1'b1 && MEM_n == 1'b0) || cpu_mem_write_pending == 1'b1) begin
          // init CPU write cycle
          addr <= xaddr_bus;
          mem_state <= cpu_pre_wr2;     
          // signals moved from here to cpu_pre_wr2, the CPU data bus out not ready yet        
        end 
      end
      wr0 : begin
        ram_cs_n <= 1'b0;
        // issue write strobes
        sram_we_n <= 1'b0;
        mem_state <= wr1;
      end
      wr1 : mem_state <= wr2; // waste time
      wr2 : begin
        // terminate memory write cycle
        sram_we_n <= 1'b1;
        ram_cs_n <= 1'b1;
        mem_drive_bus <= 1'b0;
        mem_state <= grace;
        if(flashLoading == 1'b0) begin
          mem_write_ack <= 1'b1;
        end
      end
      // states to handle read cycles
      rd0 : begin
        ram_cs_n <= 1'b0;     // init read cycle
        sram_oe_n <= 1'b0;
        mem_state <= rd1;
      end
      rd1 : mem_state <= rd2; // waste some time
      rd2 : begin
        if(mem_addr[0] == 1'b1) begin
          mem_data_in <= SRAM_DAT_in[7:0];
        end
        else begin
          mem_data_in <= SRAM_DAT_in[15:8];
        end
        ram_cs_n <= 1'b1;
        sram_oe_n <= 1'b1;
        mem_state <= grace;
        mem_read_ack <= 1'b1;
      end
      grace : begin
        // one cycle grace period before going idle.
        mem_state <= idle;
        // thus one cycle when mem_write_rq is not sampled after write.
        mem_read_ack <= 1'b0;
        mem_write_ack <= 1'b0;
        ram_cs_n <= 1'b1;
        // since we can enter here from cache hits, make sure SRAM is deselected
        sram_oe_n <= 1'b1;
        // CPU read cycle
      end
      cpu_rd2 : begin
        data_read_for_cpu <= SRAM_DAT_in;
        ram_cs_n <= 1'b1;
        sram_oe_n <= 1'b1;
        cpu_rd_ack <= 1'b1;
        mem_state <= idle; // grace;
        // Optimization: If VDP is requesting read access, go there directly, instead of idle.
        // if(vdp_read_rq || vdp_read_pending) begin
        //   // Same code as in the idle state.
        //   vdp_read_pending <= 1'b0;
        //   addr <= { 5'b01000, vdp_addr[13:1]};  // VRAM at 128K
        //   accessor <= access_vdp;
        //   ram_cs_n <= 1'b0;                 // init read cycle
        //   sram_oe_n <= 1'b0;
        //   mem_drive_bus <= 1'b0;
        //   mem_state <= vdp_rd0;
        // end
      end
      // CPU write cycle
      cpu_pre_wr2 : begin
          ram_cs_n <= 1'b0;                 // initiate write cycle
          sram_we_n <= 1'b0;
          mem_drive_bus <= 1'b1;            // only writes drive the bus   (for non-CPU writes)
          cpu_mem_write_pending <= 1'b0;
          accessor <= access_cpu;
          SRAM_DAT_out <= data_from_cpu;
          SRAM_BE <= 2'b00;

          mem_state <= cpu_wr2;     
      end
      cpu_wr2 : begin
        sram_we_n <= 1'b1;
        ram_cs_n <= 1'b1;
        mem_drive_bus <= 1'b0;
        cpu_wr_ack <= 1'b1;
        mem_state <= grace;
      end
      vdp_rd0: begin
        vdp_data_out <= vdp_last_addr0 ? SRAM_DAT_in[7:0] : SRAM_DAT_in[15:8];
        if (vdp_pipeline_reads) begin
          // Stay in this state and continue to read stuff from different addresses.
          // Only issue ack for the very first read in a pipelined read stream.
          if (vdp_first_pipelined_read)
            vdp_read_ack <= 1'b1;
          vdp_first_pipelined_read <= 1'b0;
          vdp_read_pending <= 1'b0;             // Don't remember pending reads during pipelining.
          addr <= { 5'b01000, vdp_addr[13:1]};  // VRAM at 128K
          vdp_last_addr0 <= vdp_addr[0];        // Remember LSB for for pipeline byte select
          SRAM_BE <= { vdp_addr[0], ~vdp_addr[0] };
        end else begin
          ram_cs_n <= 1'b1;
          sram_oe_n <= 1'b1;
          mem_state <= idle; 
          if (vdp_first_pipelined_read)
            vdp_read_ack <= 1'b1;               // Don't issue an extra tail end ack
        end
      end
      vdp_wr0: begin
        // Bring now write strobe low, address & data are stable
        sram_we_n <= 1'b0;
        mem_state <= vdp_wr1;
      end
      vdp_wr1: begin
        sram_we_n <= 1'b1;
        ram_cs_n <= 1'b1;
        mem_drive_bus <= 1'b0;
        mem_state <= grace;
        vdp_write_ack <= 1'b1;
      end
      endcase
    end
  end


endmodule
