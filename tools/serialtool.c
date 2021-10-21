// serialtool.c
// Serial port communication from Mac OS.
// Inspiration: https://www.pololu.com/docs/0J73/15.5
 
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <stdint.h>
#include <termios.h>
 

unsigned fpga_addr=0;

// Opens the specified serial port, sets it up for binary communication,
// configures its read timeouts, and sets its baud rate.
// Returns a non-negative file descriptor on success, or -1 on failure.
int open_serial_port(const char * device, uint32_t baud_rate)
{
  int fd = open(device, O_RDWR | O_NOCTTY);
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

int try_sync(int fd) {
	uint8_t buf[16];
	unsigned long realsize;
	// printf("%s\n", __PRETTY_FUNCTION__);
  write_port(fd, (uint8_t *)".", 1);
	buf[0] = 0;
  int bytes;
  if((bytes = read_port(fd, buf, 1)) < 1) {
      fprintf(stderr, "Timeout in %s\n", __PRETTY_FUNCTION__);
      return 0;
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
 
int main(int argc, char *argv[])
{
  // Choose the serial port name.  If the Jrk is connected directly via USB,
  // you can run "jrk2cmd --cmd-port" to get the right name to use here.
  // Linux USB example:          "/dev/ttyACM0"  (see also: /dev/serial/by-id)
  // macOS USB example:          "/dev/cu.usbmodem001234562"
  // Cygwin example:             "/dev/ttyS7"
  const char * device = "/dev/ttyACM0";
  if(argc > 1)
    device = argv[1];
 
  uint32_t baud_rate = 230400;
 
  printf("open_serial_port\n");
  int fd = open_serial_port(device, baud_rate);
  if (fd < 0) { return 1; }
 
  if(try_sync(fd)) {
    printf("Sync succeeded\n");
  }

  int ok = 0;
  unsigned a = read_hw_address(fd, &ok);
  printf("hw addr=0x%X ok=%d\n", a, ok);
  printf("Repeat counter: %d\n", get_repeat_counter_16(fd));
  setup_hw_address(fd, 0x123456);
  set_repeat_counter_16(fd, 0x2112);
  a = read_hw_address(fd, &ok);
  printf("hw addr=0x%X ok=%d\n", a, ok);
  printf("Repeat counter: 0x%X\n", get_repeat_counter_16(fd));
  
  if(try_sync(fd)) {
    printf("Sync succeeded\n");
  }


  close(fd);
  return 0;
}

