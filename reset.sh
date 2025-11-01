#!/bin/sh
# Reset the TI-99/4A FPGA CPU by sending the 'FC' command over serial
tools/serialtool -p 1000008 FC
tools/serialtool -p 1000008 FF
echo "Sent reset command to TI-99/4A FPGA CPU."
