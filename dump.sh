#!/bin/sh

dir=dump/`hostname -s`

dump() {
	mkdir -p $dir/`dirname $1`
	cat $1 > $dir/$1
}

dump /proc/device-tree/model
dump /sys/kernel/debug/pinctrl/pinctrl-handles
ls -d /sys/devices/platform/soc*/*.serial/tty/tty* | while read path ; do
	mkdir -p $dir/$path
done

