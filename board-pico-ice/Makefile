# Makefile for pico-ice board with icy99 TI-99/4A implementation
# Author: Erik Piehl
# Adapted from my board-ulx3s/Makefile
# This is a very small FPGA compared to the ECP5 chips.
# Therefore LCD, or OSD support is included. Also other things may be cut if needed.
# There is not enough internal block RAM for ROM memories, so an external SPI flash is used for that.

# APIO package manager paths 
# YOSYSPATH := $(shell echo $(HOME)/.apio/packages/tools-oss-cad-suite/bin)
YOSYSPATH := $(shell echo $(HOME)/.apio/packages/oss-cad-suite/bin)
export YOSYSPATH

# Build options. For pico-ice, SDRAM_SUPPORT means support for external PSRAM chip.
SDRAM_SUPPORT ?= 0

# Get hostname for build directory (like FleaFPGA Makefile)
HOSTNAME := $(shell hostname)

# Define compilation flags
#  -DLCD_SUPPORT
DEFINES =
ifeq ($(SDRAM_SUPPORT),1)
    DEFINES += -DUSE_SDRAM
    PROJ = pico_ice_sdram
else
    PROJ = pico_ice_nosdram
endif

# Target files
TOP_MODULE = top_pico_ice
VERILOG_FILES = \
	$(TOP_MODULE).v \
    ../src/dvi.v \
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
    ../lcd/ram_source.v 

# ECP5 device (ULX3S uses ECP5-85F - the largest chip in BGA381 package)
DEVICE = --up5k --package sg48

# Build directories
BUILD_DIR = $(HOSTNAME)
BITSTREAM = $(BUILD_DIR)/$(PROJ).bit

# Default target
all: $(BUILD_DIR)/$(PROJ).uf2

# JSON synthesis
$(BUILD_DIR)/$(PROJ).json: $(VERILOG_FILES) | $(BUILD_DIR)
	@echo "Synthesizing design with Yosys..."
	cd $(BUILD_DIR) && $(YOSYSPATH)/yosys -q -p "synth_ice40 -json $(PROJ).json" $(DEFINES) $(addprefix ../,$(VERILOG_FILES))

# Place and route
$(BUILD_DIR)/$(PROJ)_out.asc: $(BUILD_DIR)/$(PROJ).json pico_ice.pcf
	@echo "Place and route with NextPNR..."
	$(YOSYSPATH)/nextpnr-ice40 $(DEVICE) --json $(BUILD_DIR)/$(PROJ).json --pcf pico_ice.pcf --asc $@

# Generate bitstream
$(BITSTREAM): $(BUILD_DIR)/$(PROJ)_out.asc
	@echo "Generating bitstream with icepack..."
	rm -f $@
	$(YOSYSPATH)/icepack $< $@

$(BUILD_DIR)/$(PROJ).uf2: $(BITSTREAM)
	rm -f $@	
	bin2uf2 -o $@ $<	

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)


# Clean build files for current configuration
clean:
	rm -f $(BUILD_DIR)/$(PROJ).json
	rm -f $(BUILD_DIR)/$(PROJ)_out.cfg
	rm -f $(BITSTREAM)

# Clean all build files (both SDRAM and non-SDRAM)
cleanall:
	rm -rf $(BUILD_DIR)

# Show resource usage
resource-usage: $(BUILD_DIR)/$(PROJ)_out.asc
	@echo "Resource utilization:"
	@grep -A 20 "Device utilisation:" $(BUILD_DIR)/nextpnr.log || echo "Run place and route first"

# Build without SDRAM support
no-sdram:
	$(MAKE) SDRAM_SUPPORT=0

# Build with SDRAM support (default)
sdram:
	$(MAKE) SDRAM_SUPPORT=1

reset:
	../tools/serialtool -p 1000008 FC
	../tools/serialtool -p 1000008 FF

enter1:
	../tools/serialtool -p 1000005 ef
	../tools/serialtool -p 1000005 ff
	
enter2:
	../tools/serialtool -p 1000001 ef
	../tools/serialtool -p 1000001 ff

load_parsec:
	# Parsec ROM
	../tools/serialtool -w ../dev-sd/cart/parsecc.bin 200000 8192
	# Parsec GROM
	../tools/serialtool -w ../dev-sd/grom/parsecg.bin 16000 24576


# Show help
help:
	@echo "ULX3S icy99 TI-99/4A Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build bitstream (default)"
	@echo "  clean      - Clean current build files"
	@echo "  cleanall   - Clean all build files"
	@echo "  sdram      - Build with SDRAM support (default)"
	@echo "  no-sdram   - Build without SDRAM support"
	@echo "  help       - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  SDRAM_SUPPORT=1|0      - Enable/disable SDRAM (default: 0)"
	@echo ""
	@echo "Examples:"
	@echo "  make SDRAM_SUPPORT=1 - Build with SDRAM"

.PHONY: all prog ujprog clean cleanall resource-usage no-sdram sdram help
