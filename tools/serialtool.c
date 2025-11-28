// serialtool.c
// Serial port communication from Mac OS.
// Inspiration: https://www.pololu.com/docs/0J73/15.5
 
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <termios.h>
#include <string.h>
 

unsigned fpga_addr=0;
int verbose = 0;
int write_delay_us = 0;  // Microsecond delay after writes (for RP2040 USB-CDC)
int block_size = 1024;   // Block size for write operations (default 1024)

// Opens the specified serial port, sets it up for binary communication,
// configures its read timeouts, and sets its baud rate.
// Returns a non-negative file descriptor on success, or -1 on failure.
int open_serial_port(const char * device, uint32_t baud_rate)
{
  int fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
  if (fd == -1)
  {
    perror(device);
    return -1;
  }
 
  // Flush away any bytes previously read or written.
  int result = tcflush(fd, TCIOFLUSH);
  if (result)
  {
    perror("tcflush failed");  // just a warning, not a fatal error
  }
 
  // Get the current configuration of the serial port.
  struct termios options;
  result = tcgetattr(fd, &options);
  if (result)
  {
    perror("tcgetattr failed");
    close(fd);
    return -1;
  }
 
  // Turn off any options that might interfere with our ability to send and
  // receive raw binary bytes.
  options.c_iflag &= ~(INLCR | IGNCR | ICRNL | IXON | IXOFF);
  options.c_oflag &= ~(ONLCR | OCRNL);
  options.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  options.c_cflag &= ~CRTSCTS;  // Disable hardware flow control
  options.c_cflag |= CLOCAL;    // Ignore modem control lines
 
  // Set up timeouts: Calls to read() will return as soon as there is
  // at least one byte available or when 100 ms has passed.
  options.c_cc[VTIME] = 1;
  options.c_cc[VMIN] = 0;
 
  // This code only supports certain standard baud rates. Supporting
  // non-standard baud rates should be possible but takes more work.
  switch (baud_rate)
  {
  case 4800:   cfsetospeed(&options, B4800);   break;
  case 9600:   cfsetospeed(&options, B9600);   break;
  case 19200:  cfsetospeed(&options, B19200);  break;
  case 38400:  cfsetospeed(&options, B38400);  break;
  case 115200: cfsetospeed(&options, B115200); break;
  case 230400: cfsetospeed(&options, B230400); break;
  default:
    fprintf(stderr, "warning: baud rate %u is not supported, using 9600.\n",
      baud_rate);
    cfsetospeed(&options, B9600);
    break;
  }
  cfsetispeed(&options, cfgetospeed(&options));
 
  result = tcsetattr(fd, TCSANOW, &options);
  if (result)
  {
    perror("tcsetattr failed");
    close(fd);
    return -1;
  }
 
  // Clear O_NONBLOCK flag to allow blocking reads/writes
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags != -1)
  {
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
  }
 
  return fd;
}
 
// Writes bytes to the serial port, returning 0 on success and -1 on failure.
int write_port(int fd, uint8_t * buffer, size_t size)
{
  ssize_t result = write(fd, buffer, size);
  if (result != (ssize_t)size)
  {
    perror("failed to write to port");
    return -1;
  }
  if (write_delay_us > 0) {
    usleep(write_delay_us);
  }
  return 0;
}
 
// Reads bytes from the serial port.
// Returns after all the desired bytes have been read, or if there is a
// timeout or other error.
// Returns the number of bytes successfully read into the buffer, or -1 if
// there was an error reading.
ssize_t read_port(int fd, uint8_t * buffer, size_t size)
{
  size_t received = 0;
  while (received < size)
  {
    ssize_t r = read(fd, buffer + received, size - received);
    if (r < 0)
    {
      perror("failed to read from port");
      return -1;
    }
    if (r == 0)
    {
      // Timeout
      break;
    }
    received += r;
  }
  return received;
}

int try_sync(int fd, int verbose) {
	uint8_t buf[16];
	// printf("%s\n", __PRETTY_FUNCTION__);
  write_port(fd, (uint8_t *)".", 1);
	buf[0] = 0;
  int bytes;
  if((bytes = read_port(fd, buf, 1)) < 1) {
      fprintf(stderr, "Timeout in %s\n", __PRETTY_FUNCTION__);
      return 0;
  }        
  if(verbose) {
    if(buf[0] != '.') {
      fprintf(stderr, "try_sync read %d bytes, expected '.', got 0x%02X\n", bytes, buf[0]);
    }
  }
  return bytes > 0 && buf[0] == '.';
}

void setup_hw_address(int fd, unsigned addr) {
	unsigned char buf[16] = { "A_B_C_D_" };
	buf[1] = addr;
	buf[3] = addr >> 8;
	buf[5] = addr >> 16;
	buf[7] = addr >> 24;
	write_port(fd, buf, 8);
	fpga_addr = addr;
}

unsigned read_hw_address(int fd, int *ok) {
	uint8_t buf[8] = { "EFGH" };
	*ok = 0;
	// printf("%s\n", __PRETTY_FUNCTION__);
  write_port(fd, &buf[0], 1);
  read_port(fd, buf, 1);
  write_port(fd, &buf[1], 1);
  read_port(fd, buf+1, 1);
  write_port(fd, &buf[2], 1);
  read_port(fd, buf+2, 1);
  write_port(fd, &buf[3], 1);
  read_port(fd, buf+3, 1);
	*ok = 1;
	return buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
}


void set_repeat_counter_16(int fd, int len) {
    unsigned char cmd[3] = { 'T', 0, 0 };
    cmd[1] = len & 0xFF;
    cmd[2] = len >> 8;
    write_port(fd, cmd, 3);
}

unsigned get_repeat_counter_16(int fd) {
  unsigned char buf[2];
  unsigned k;
  // Send read command
  write_port(fd, (uint8_t *)"P", 1);
  // Receive our bytes
  read_port(fd, buf, 2);
  k = buf[0] | (buf[1] << 8);
  return k;
}

int receive_block_complete(int fd, void *block, size_t size, unsigned timeout) {
  unsigned realsize = 0;
  uint8_t *result;
	// unsigned now = GetTickCount();
  result = (uint8_t *) block;
  // SerialTimeoutSet(timeout);

  do {
    ssize_t read = read_port(fd, result + realsize, size - realsize);
    realsize += read;
		// loops++;  // undefined variable, commented out
		
		if (realsize < size)
			sleep(1);

  } while(realsize < size); 
  // while ((realsize < size) && (SerialTimeoutCheck() == 0));  
  return realsize == size ? 0 : 1;
}

void read_memory_block(int fd, unsigned char *dest, unsigned address, int len) {
  setup_hw_address(fd, address);
  // Enable autoincrement mode and configure length
  write_port(fd, (uint8_t *)"M3", 2);
  set_repeat_counter_16(fd, len);
  // Send read command and read our stuff
  write_port(fd, (uint8_t *)"@", 1);
  receive_block_complete(fd, dest, len, 2000);
}

int write_memory_block(int fd, unsigned char *source, unsigned address, int len) {
  int chunk = len > block_size ? block_size : len;
  setup_hw_address(fd, address);
  // Enable autoincrement mode and configure length
  if(write_port(fd, (uint8_t *)"M3", 2))
    return -1;
  set_repeat_counter_16(fd, chunk);
  // Send write command and write our stuff
  if(write_port(fd, (uint8_t *)"!", 1))
    return -2;
  if(write_port(fd, source, chunk))
    return -3;
  if(!try_sync(fd, verbose)) {
    return -4;
  }
  return chunk;
}

int load_file(int fd, char *filename, unsigned addr) {
  FILE *f = fopen(filename, "rb");
  if(!f) {
    fprintf(stderr, "Unable to open source file\n");
    return -1;
  }
  uint8_t buf[1024];
  int total = 0;
  int n;
  do {
    n = fread(buf, sizeof(uint8_t), sizeof(buf), f);
    if(n > 0) {
      // Write may be partial due to block_size, loop until all bytes written
      int offset = 0;
      while(offset < n) {
        int r = write_memory_block(fd, buf + offset, addr, n - offset);
        if(r < 0) {
          fprintf(stderr, "write_memory_block failed %d\n", r);
          fclose(f);
          return r;
        }
        addr += r;
        offset += r;
        total += r;
      }
    }
  } while(n > 0);
  printf("load_file done, wrote %d bytes, final address %X\n", total, addr);
  return 0;
}

void print_help(const char *progname) {
  printf("Usage: %s [options] <command> [arguments]\n\n", progname);
  printf("Options:\n");
  printf("  --port <port>      Specify serial port (overrides SERIALTOOL_PORT env var)\n");
  printf("  --delay <us>       Add delay in microseconds after each write (for RP2040)\n");
  printf("  --block-size <n>   Set write block size in bytes (default: 1024)\n");
  printf("  -v                 Enable verbose output\n");
  printf("  Environment variable SERIALTOOL_PORT can be set to avoid specifying port\n\n");
  printf("Commands:\n");
  printf("  -w <filename> <address> <length>  Write file to memory\n");
  printf("                                     address: hex address to write to\n");
  printf("                                     length: number of bytes to write\n");
  printf("  -r <filename> <address> <length>  Read memory to file\n");
  printf("                                     address: hex address to read from\n");
  printf("                                     length: number of bytes to read\n");
  printf("  -a                                 Get current hardware address\n");
  printf("  -p <address> <byte1> [byte2...]   Poke (write) bytes to memory\n");
  printf("                                     address: hex address to write to\n");
  printf("                                     bytes: hex bytes to write\n");
  printf("  -P <address> [count]               Peek (read) bytes from memory\n");
  printf("                                     address: hex address to read from\n");
  printf("                                     count: number of bytes (default: 1)\n");
  printf("\nExamples:\n");
  printf("  export SERIALTOOL_PORT=/dev/ttyACM0\n");
  printf("  %s -w firmware.bin 8000 1024\n", progname);
  printf("  %s -r dump.bin 0 8192\n", progname);
  printf("  %s --port /dev/ttyUSB0 -p 1000 ff aa 55\n", progname);
  printf("  %s -P 1000 16\n", progname);
  printf("  %s -a\n", progname);
}
 
int main(int argc, char *argv[])
{
  if(argc < 2) {
    print_help(argv[0]);
    return 1;
  }

  // Get serial port from environment variable or command line
  const char * device = getenv("SERIALTOOL_PORT");
  if(!device) {
    device = "/dev/ttyACM0";  // Default fallback
  }
  
  verbose = 0;  // Use global verbose variable
  if(verbose) printf("argc %d\n", argc);
  int argi = 1;
  
  // Check for options
  while(argi < argc && argv[argi][0] == '-') {
    if(!strcmp(argv[argi], "--port")) {
      if(argi + 1 >= argc) {
        fprintf(stderr, "Error: --port requires an argument\n");
        print_help(argv[0]);
        return 1;
      }
      device = argv[argi + 1];
      argi += 2;
    } else if(!strcmp(argv[argi], "--delay")) {
      if(argi + 1 >= argc) {
        fprintf(stderr, "Error: --delay requires an argument\n");
        print_help(argv[0]);
        return 1;
      }
      write_delay_us = atoi(argv[argi + 1]);
      if(verbose) printf("Write delay set to %d microseconds\n", write_delay_us);
      argi += 2;
    } else if(!strcmp(argv[argi], "--block-size")) {
      if(argi + 1 >= argc) {
        fprintf(stderr, "Error: --block-size requires an argument\n");
        print_help(argv[0]);
        return 1;
      }
      block_size = atoi(argv[argi + 1]);
      if(block_size < 1 || block_size > 1024) {
        fprintf(stderr, "Error: block size must be between 1 and 1024\n");
        return 1;
      }
      if(verbose) printf("Block size set to %d bytes\n", block_size);
      argi += 2;
    } else if(!strcmp(argv[argi], "-v")) {
      verbose = 1;
      argi++;
    } else {
      // Not an option we recognize, might be a command
      break;
    }
  }
  
  // Check if we have a command after port parsing
  if(argi >= argc) {
    print_help(argv[0]);
    return 1;
  }
 
  uint32_t baud_rate = 230400;
 
  if(verbose) printf("open_serial_port\n");
  int fd = open_serial_port(device, baud_rate);
  if (fd < 0) { return 1; }

  if (verbose)  
    printf("Opened serial port %s at %u baud\n", device, baud_rate);

  int in_sync = 0;
  for(int tries = 0; tries < 512; tries++) {
    if(try_sync(fd, verbose)) {
      if(verbose || tries > 0) printf("Sync succeeded\n");
      in_sync = 1;
      break;
    } else {
      fprintf(stderr, "Sync failed, retrying %d\n", tries);
    }
  }
  if(!in_sync) {
    fprintf(stderr, "Sync failed, exiting.\n");
    close(fd);
    return 1;
  }

  // Parse command line arguments
  // argv[argi] == -w or -r for write and read respectively
  // argv[argi+1] == filename
  // argv[argi+2] == address (in hex)
  // argv[argi+3] == length
  enum { MODE_NONE, MODE_WRITE, MODE_READ, MODE_GET_ADDR, MODE_POKE, MODE_PEEK } mode = MODE_NONE;
  // Parse options i.e. strings beginning with '-'
  while(argi < argc && argv[argi][0] == '-') {
    if(!strcmp(argv[argi], "-w")) {
      mode = MODE_WRITE;
    } else if(!strcmp(argv[argi], "-r")) {
      mode = MODE_READ;
    }  else if(!strcmp(argv[argi], "-a")) {
      mode = MODE_GET_ADDR;
    }  else if(!strcmp(argv[argi], "-p")) {
      mode = MODE_POKE;
    }  else if(!strcmp(argv[argi], "-P")) {
      mode = MODE_PEEK;
    } else {
      fprintf(stderr, "Invalid option %s\n", argv[argi]);
      close(fd);
      return 1;
    }
    argi++;
  }
  if(mode == MODE_NONE) {
    fprintf(stderr, "No mode specified\n");
    close(fd);
    return 1;
  }
  if(mode == MODE_GET_ADDR) {
    int ok = 0;
    unsigned addr = read_hw_address(fd, &ok);
    if(ok) {
      printf("HW address: %X\n", addr);
    } else {
      fprintf(stderr, "Failed to read HW address\n");
    }
    close(fd);
    return 0;
  } else if (mode == MODE_POKE) {
    if(argi + 1 >= argc) {
      fprintf(stderr, "Not enough arguments\n");
      close(fd);
      return 1;
    }
    unsigned addr;
    if(sscanf(argv[argi++], "%x", &addr) != 1) {
      fprintf(stderr, "Invalid address\n");
      close(fd);
      return 1;
    }
    setup_hw_address(fd, addr);
    // read hex argument bytes and write them to the address
    while(argi < argc) {
      unsigned byte;
      if(sscanf(argv[argi++], "%x", &byte) != 1) {
        fprintf(stderr, "Invalid byte\n");
        close(fd);
        return 1;
      }
      uint8_t buf[1] = { byte };
      write_memory_block(fd, buf, addr++, 1);
    }
    close(fd);
    return 0;
  } else if (mode == MODE_PEEK) {
    if(argi >= argc) {
      fprintf(stderr, "Not enough arguments\n");
      close(fd);
      return 1;
    }
    unsigned addr;
    if(sscanf(argv[argi++], "%x", &addr) != 1) {
      fprintf(stderr, "Invalid address\n");
      close(fd);
      return 1;
    }
    int num_bytes = 1;  // Default to 1 byte
    if(argi < argc) {
      if(sscanf(argv[argi++], "%x", &num_bytes) != 1) {
        fprintf(stderr, "Invalid number of bytes\n");
        close(fd);
        return 1;
      }
    }
    if(num_bytes < 1 || num_bytes > 1024) {
      fprintf(stderr, "Number of bytes must be between 1 and 1024\n");
      close(fd);
      return 1;
    }
    uint8_t buf[1024];
    read_memory_block(fd, buf, addr, num_bytes);
    for(int i = 0; i < num_bytes; i++) {
      if(i % 16 == 0) {
        if(i > 0) {
          printf("\n");
        }
        printf("%06x: ", addr + i);
      }
      printf("%02x", buf[i]);
      if(i < num_bytes - 1 && (i + 1) % 16 != 0) {
        printf(" ");
      }
    }
    printf("\n");
    close(fd);
    return 0;
  }
  if(argi + 2 >= argc) {
    fprintf(stderr, "Not enough arguments\n");
    close(fd);
    return 1;
  }
  const char *filename = argv[argi++];
  unsigned address;
  if(sscanf(argv[argi++], "%x", &address) != 1) {
    fprintf(stderr, "Invalid address\n");
    close(fd);
    return 1;
  } else {
    if(verbose) printf("Address: %X\n", address);
  }
  int length;
  if(sscanf(argv[argi++], "%d", &length) != 1) {
    fprintf(stderr, "Invalid length\n");
    close(fd);
    return 1;
  } else {
    if(verbose) printf("Length: %d\n", length);
  }
  if(mode == MODE_WRITE) {
    FILE *f = fopen(filename, "rb");
    if(!f) {
      fprintf(stderr, "Unable to open source file\n");
      close(fd);
      return 1;
    } else {
      if(verbose) printf("Opened source file %s\n", filename);
    }
    uint8_t buf[1024];
    int total = 0;
    int n;
    do {
      int bytes_to_read = total + sizeof(buf) > length ? length - total : sizeof(buf);
      n = fread(buf, sizeof(uint8_t), bytes_to_read, f);
      if(n < bytes_to_read && n != 0) {
        length = total + n;
        printf("Short read, adjusting length to %d\n", length);
      }
      if(n > 0) {
        // Write may be partial due to block_size, loop until all bytes written
        int offset = 0;
        while(offset < n) {
          int r = write_memory_block(fd, buf + offset, address, n - offset);
          if(r < 0) {
            fprintf(stderr, "write_memory_block failed %d\n", r);
            fclose(f);
            close(fd);
            return 1;
          }
          if(verbose) printf("Wrote %d bytes at address %X\n", r, address);
          address += r;
          offset += r;
          total += r;
        }
      }
    } while(n > 0);
    printf("load_file done, wrote %d bytes, final address %X\n", total, address);
  } else if(mode == MODE_READ) {
    // Read memory blocks in chunks of a maximum of 1024 bytes
    uint8_t buf[1024];
    FILE *f = fopen(filename, "wb");
    if(!f) {
      fprintf(stderr, "Unable to open destination file\n");
      close(fd);
      return 1;
    } else {
      printf("Opened destination file %s\n", filename);
      unsigned read = 0;
      while(read < length) {
        int chunk = length - read;
        if(chunk > 1024) {
          chunk = 1024;
        }
        read_memory_block(fd, buf, address, chunk);
        fwrite(buf, sizeof(uint8_t), chunk, f);
        read += chunk;
        address += chunk;
      }
      fclose(f);
    }
  }
  // Check that we are still in sync
  if(try_sync(fd, verbose)) {
    if(verbose) printf("Sync succeeded\n");
  } else {
    fprintf(stderr, "Sync failed at the end, exiting.\n");
    close(fd);
    return 1;
  }

  close(fd);
  return 0;



 
 
  if(argc > 3 && !strcmp(argv[2], "-l")) {
    // argv[1] = port
    // argv[2] = -l 
    // argv[3] = filename
    // argv[4] = address (in hex)
    unsigned a;
    int r = sscanf(argv[4], "%x", &a);
    printf("r, a %X %X\n", a, r);

  } else { 

  if(try_sync(fd, verbose)) {
      printf("Sync succeeded\n");
    }


    int ok = 0;
    unsigned a = read_hw_address(fd, &ok);
    printf("hw addr=0x%X ok=%d\n", a, ok);
    printf("Repeat counter: %d\n", get_repeat_counter_16(fd));
    unsigned addr = 0x123456;
    printf("Write hw_address %08X\n", addr);
    setup_hw_address(fd, addr);
    set_repeat_counter_16(fd, 0x2112);
    a = read_hw_address(fd, &ok);
    printf("hw addr=0x%X ok=%d\n", a, ok);
    printf("Repeat counter: 0x%X\n", get_repeat_counter_16(fd));
    
    if(try_sync(fd, verbose)) {
      printf("Sync succeeded\n");
    }
  }

  close(fd);
  return 0;
}

