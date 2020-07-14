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

  # LOAD/SAVE and CPU control

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, maxlen=0x10000, blocksize=1024):
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
    addr=0x40000
    tight=0
    if filename.startswith("/sd/ti99_4a/cart"):
      addr=0x40000
    if filename.startswith("/sd/ti99_4a/grom"):
      addr=0x16000
    if filename.startswith("/sd/ti99_4a/dsr"):
      addr=0x4000
    if filename.endswith("8.bin"):
      addr=0x40000
    if filename.endswith("c.bin"):
      addr=0x40000
    if filename.endswith("d.bin"):
      addr=0x42000
    if filename.endswith("g.bin"):
      addr=0x16000
    if filename.endswith("g3.bin"):
      addr=0x16000
    if filename.endswith("g4.bin"):
      addr=0x18000
    if filename.endswith("g5.bin"):
      addr=0x1A000
    if filename.endswith("g6.bin"):
      addr=0x1C000
    if filename.endswith("g7.bin"):
      addr=0x1E000
    if filename.endswith("6k.bin"):
      addr=0x16000
      tight=1
    if tight:
      self.load_grom_tight(filedata,addr)
    else:
      self.load_stream(filedata,addr)
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
