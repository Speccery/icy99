# micropython ESP32
# TI99/4A (icy99) ROM image loader

# AUTHOR=EMARD
# LICENSE=BSD

class ld_ti99_4a:
  def __init__(self,spi,cs):
    self.spi=spi
    self.spi.init(baudrate=1000000) # 1 MHz
    self.cs=cs
    self.cs.off()
    self.cart_rom_region = 0x200000
    self.cart_grom_region = 0x16000
    self.cart_tipi_region = 0x30000

  # LOAD/SAVE and CPU control

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, maxlen=0x200000, blocksize=1024):
    block = bytearray(blocksize)
    # Request load
    self.cs.on()
    self.spi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    bytes_loaded = 0
    while bytes_loaded < maxlen:
      if filedata.readinto(block):
        self.spi.write(block)
        bytes_loaded += blocksize
      else:
        break
    self.cs.off()

  # tight GROM file (no padding)
  # each 6K block from this file is written to even 8K address
  def load_grom_tight(self, filedata, addr=0, maxlen=0x80000, blocksize=1024):
    block = bytearray(blocksize)
    bytes_loaded = 0
    while bytes_loaded < maxlen:
      # Request load
      self.cs.on()
      self.spi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
      grom_loaded = 0
      while grom_loaded < 6144:
        if filedata.readinto(block):
          self.spi.write(block)
          grom_loaded += blocksize
        else:
          bytes_loaded = maxlen # force exit of outer loop
          break
      self.cs.off()
      bytes_loaded += 6144
      addr += 8192

  # filename used to detect what ROM it is and where to load
  def load_rom_auto(self, filedata, filename=""):
    addr=self.cart_rom_region
    tight=0
    fname = filename.lower()
    if fname.startswith("/sd/ti99_4a/cart"):
      addr=self.cart_rom_region
    if fname.startswith("/sd/ti99_4a/grom"):
      addr=self.cart_grom_region
    if fname.startswith("/sd/ti99_4a/dsr"):
      addr=self.cart_tipi_region   # DSR routines to drive TIPI
    if fname.endswith("8.bin"):
      addr=self.cart_rom_region
    if fname.endswith("c.bin"):
      addr=self.cart_rom_region
    if fname.endswith("d.bin"):
      addr=self.cart_rom_region+0x2000
    if fname.endswith("g.bin"):
      addr=self.cart_grom_region
    if fname.endswith("g3.bin"):
      addr=self.cart_grom_region
    if fname.endswith("g4.bin"):
      addr=self.cart_grom_region+0x2000
    if fname.endswith("g5.bin"):
      addr=self.cart_grom_region+0x4000
    if fname.endswith("g6.bin"):
      addr=self.cart_grom_region+0x6000
    if fname.endswith("g7.bin"):
      addr=self.cart_grom_region+0x8000
    if fname.endswith("6k.bin"):
      addr=self.cart_grom_region
      tight=1
    if tight:
      self.load_grom_tight(filedata,addr)
    else:
      self.load_stream(filedata,addr)
      print("Loaded {} at {}".format(filename, hex(addr)))
    self.reset_on()
    self.reset_off()

  # read from SPI RAM -> write to file
  def save_stream(self, filedata, addr=0, length=1024, blocksize=1024):
    bytes_saved = 0
    block = bytearray(blocksize)
    # Request save
    self.cs.on()
    self.spi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
    while bytes_saved < length:
      self.spi.readinto(block)
      filedata.write(block)
      bytes_saved += len(block)
    self.cs.off()

  def ctrl(self,i):
    self.cs.on()
    self.spi.write(bytearray([0, 0x00, 0x10, 0x00, 0x08, i]))
    self.cs.off()

  def reset_on(self):
    self.ctrl(0xFC)

  def reset_off(self):
    self.ctrl(0xFF)
