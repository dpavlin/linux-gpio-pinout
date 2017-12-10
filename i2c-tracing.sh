#!/bin/sh

if [ -z "$1" ] ; then
	echo "Usage: $0 0|1 - disable/enable i2c tracking"
	exit 1
fi

echo $1 > /sys/kernel/debug/tracing/events/i2c/enable
# echo adapter_nr==1 >/sys/kernel/debug/tracing/events/i2c/filter
cat /sys/kernel/debug/tracing/trace
