#!/bin/sh -xe

sudo apt-get install libdata-dump-perl
uname -a | grep sunxi && \
apt-cache search --names-only '^sunxi-tools$' | cut -d' ' -f1 | xargs -i sudo apt-get install {}
apt-cache search --names-only '^raspi-gpio$'  | cut -d' ' -f1 | xargs -i sudo apt-get install {}
