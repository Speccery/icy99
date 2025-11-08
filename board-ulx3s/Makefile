# Makefile for ULX3S board with icy99 TI-99/4A implementation
# Author: Erik Piehl

# APIO package manager paths 
YOSYSPATH := $(shell echo $(HOME)/.apio/packages/tools-oss-cad-suite/bin)
export YOSYSPATH

# Build options
SDRAM_SUPPORT ?= 0

# Get hostname for build directory (like FleaFPGA Makefile)
HOSTNAME := $(shell hostname)

# Define USE_SDRAM for conditional compilation
ifeq ($(SDRAM_SUPPORT),1)
    DEFINES = -DUSE_SDRAM
    PROJ = ulx3s_sdram
else
    DEFINES = 
    PROJ = ulx3s_nosdram
endif

# Target files
TOP_MODULE = top_ulx3s
VERILOG_FILES = \
    ../src/dvi.v \
    top_ulx3s.v \
    ../rom16.v \
    ../src/ram2.v \
    ../src/sys.v \
    ../src/rom.v \
    ../src/tms9900.v \
    ../src/alu9900.v \
    ../src/tms9902.v \
    ../src/erik_pll.v \
    ../src/tms9918.v \
    ../src/vga_sync.v \
    ../src/xmemctrl.v \
    ../src/gromext.v \
    ../src/serloader.v \
    ../src/serial_rx.v \
    ../src/serial_tx.v \
    ../src/spi_slave.v \
    ../src/tms9901.v \
    ../src/dualport_par.v \
    ../src/ps2kb.v \
    ../src/tms9919.v \
    ../src/pager612.v \
    ../src/ecp5pll.sv \
    ../src/sdram_cortex.v \
    ../osd/osd.v \
    ../osd/spi_osd.v \
    ../osd/spirw_slave_v.v \
    ../osd/spi_ram_btn.v

# ECP5 device (ULX3S uses ECP5-85F - the largest chip in BGA381 package)
DEVICE = --85k --package CABGA381

# Build directories
BUILD_DIR = $(HOSTNAME)
BITSTREAM = $(BUILD_DIR)/$(PROJ).bit

# Default target
all: $(BITSTREAM)

# JSON synthesis
$(BUILD_DIR)/$(PROJ).json: $(VERILOG_FILES) | $(BUILD_DIR)
	@echo "Synthesizing design with Yosys..."
	# Copy OSD files to build directory
	@mkdir -p $(BUILD_DIR)/osd
	@cp ../osd/*.mem $(BUILD_DIR)/osd/
	cd $(BUILD_DIR) && $(YOSYSPATH)/yosys -q -p "synth_ecp5 -json $(PROJ).json" $(DEFINES) $(addprefix ../,$(VERILOG_FILES))

# Place and route
$(BUILD_DIR)/$(PROJ)_out.cfg: $(BUILD_DIR)/$(PROJ).json ulx3s.lpf
	@echo "Place and route with NextPNR..."
	$(YOSYSPATH)/nextpnr-ecp5 $(DEVICE) --json $< --lpf ulx3s.lpf --textcfg $@

# Generate bitstream
$(BITSTREAM): $(BUILD_DIR)/$(PROJ)_out.cfg
	rm -f $@
	@echo "Generating bitstream..."
	$(YOSYSPATH)/ecppack --compress $< $@
	@echo "Build complete: $@"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Program ULX3S via OpenOCD
prog: $(BITSTREAM)
	@echo "Programming ULX3S..."
	openocd -f board/ulx3s.cfg -c "transport select jtag; init; svf $<; exit"

# Program ULX3S via ujprog (alternative)
ujprog: $(BITSTREAM)
	@echo "Programming ULX3S with ujprog..."
	ujprog $<

# Clean build files for current configuration
clean:
	rm -f $(BUILD_DIR)/$(PROJ).json
	rm -f $(BUILD_DIR)/$(PROJ)_out.cfg
	rm -f $(BITSTREAM)

# Clean all build files (both SDRAM and non-SDRAM)
cleanall:
	rm -rf $(BUILD_DIR)

# Show resource usage
resource-usage: $(BUILD_DIR)/$(PROJ)_out.cfg
	@echo "Resource utilization:"
	@grep -A 20 "Device utilisation:" $(BUILD_DIR)/nextpnr.log || echo "Run place and route first"

# Build without SDRAM support
no-sdram:
	$(MAKE) SDRAM_SUPPORT=0

# Build with SDRAM support (default)
sdram:
	$(MAKE) SDRAM_SUPPORT=1

# Show help
help:
	@echo "ULX3S icy99 TI-99/4A Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build bitstream (default)"
	@echo "  prog       - Program ULX3S via OpenOCD"
  @echo "  ujprog     - Program ULX3S via ujprog"
  @echo "  clean      - Clean current build files"
  @echo "  cleanall   - Clean all build files"
  @echo "  sdram      - Build with SDRAM support (default)"
  @echo "  no-sdram   - Build without SDRAM support"
  @echo "  help       - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  SDRAM_SUPPORT=1|0  - Enable/disable SDRAM (default: 1)"

.PHONY: all prog ujprog clean cleanall resource-usage no-sdram sdram help