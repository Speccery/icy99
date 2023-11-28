# initsd.sh
# 2020-12-20
# create the directory structure on ESP32

ftp 192.168.0.160 << EOT

bin
cd /sd
mkdir ti99_4a
cd ti99_4a
mkdir grom
mkdir cart
mkdir rom
mkdir bitstreams
mkdir dsr

cd /sd/ti99_4a/bitstreams
pwd
put ti994a_ulx3s.bit
cd /
pwd
lcd esp32/osd
put osd.py
put ld_ti99_4a.py

cd /sd/ti99_4a/cart
pwd
lcd ../../debugcart
put VDP9938.bin

lcd ../roms

cd /sd/ti99_4a/rom
pwd
put 994aROM.Bin

cd ../grom
pwd
put 994AGROM.Bin

cd ../dsr
pwd
put tipi.bin

bye
EOT
