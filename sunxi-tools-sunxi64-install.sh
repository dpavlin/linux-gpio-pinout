#!/bin/sh -xe

sudo apt-get install libusb-1.0-0-dev zlib1g-dev

git clone https://github.com/linux-sunxi/sunxi-tools/
cd sunxi-tools
patch -p1 < ../sunxi-tools-PORTS_PL.diff
make
sudo make install
