# upload.sh
# Shell script to move bitstream file to the ULX3S board.
# EP 2020-12-05

ftp 192.168.0.152 << EOT

cd /sd/ti99_4a/bitstreams
pwd
put ti994a_ulx3s.bit
cd /
pwd
lcd esp32/osd
put osd.py
put ld_ti99_4a.py
bye
