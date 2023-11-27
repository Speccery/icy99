# python snippets for ESP32
# EP 2020-10-16 copied here

f=open("main.py","w")
f.write("import network\n")
f.write("sta_if = network.WLAN(network.STA_IF)\n")
f.write("sta_if.active(True)\n")
f.write('sta_if.connect("EP300N", "hulabaloo39")\n')
f.write("import uftpd\n")
f.close()



f=open("main.py")
k=f.readlines()
k
f.close()




import os
os.listdir()

from machine import SPI, Pin, SDCard, Timer
os.mount(SDCard(slot=3),"/sd")
os.listdir("/sd")
