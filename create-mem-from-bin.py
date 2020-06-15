# create-mem-from-bin.py
# An utility to read a binfile and write Verilog mem file which can be read
# using $readmemh.
# EP 2019-11-18

import sys

# write 16-bit words
def conv_to_hex_16(infile, outfile):
    count = 0
    try:
        src = open(infile, "rb")
        dst = open(outfile, "wt")

        while True:
            byte1 = src.read(1)
            byte2 = src.read(1)
            if byte1 == b"":
                break
            val = ord(byte1)*256+ord(byte2)
            dst.write("{:04X} // address 0x{:04X}\n".format(val, count*2))
            count = count+1
    finally:
        src.close()
        dst.close()
    return count*2

def conv_to_hex_8(infile, outfile):
    count = 0
    try:
        src = open(infile, "rb")
        dst = open(outfile, "wt")

        while True:
            byte1 = src.read(1)
            if byte1 == b"":
                break
            val = ord(byte1)
            dst.write("{:02X} // address 0x{:04X}\n".format(val, count))
            count = count+1
    finally:
        src.close()
        dst.close()
    return count



if __name__ == '__main__':
    # Haven't yet learned how to use argument parsing helpers, let's keep this very simple.
    if (len(sys.argv) < 3):
        print("Usage: create-mem-from-bin [-8] src dest")
        print("\tThe option -8 creates 8 bit byte based mem file, otherwise the file will contain 16-bit words.")
        exit(0)
    words = True
    i = 1;
    while sys.argv[i][0] == '-' and i<len(sys.argv):
        if sys.argv[i][1] == '8':
            words = False
        i = i + 1
    src_name = sys.argv[i]
    dest_name = sys.argv[i+1]
    
    print("Converting binary {} to hex {}".format(src_name, dest_name))
    if words:
        bytes = conv_to_hex_16(src_name, dest_name)
    else:
        print("Processing bytes")
        bytes = conv_to_hex_8(src_name, dest_name)
    print("Wrote {} bytes".format(bytes))
