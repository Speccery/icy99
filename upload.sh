# upload.sh
# Shell script to move bitstream file to the ULX3S board.
# EP 2020-12-05

ftp $1 << EOT

bin
cd /sd/ti99_4a/bitstreams
pwd
lcd EriksMacStudio.lan
put ti994a_ulx3s.bit
lcd ..
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
bye
EOT


