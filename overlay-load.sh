#!/bin/sh -xe

dtb=$1
test -f "$dtb" || ( echo "Usage: $0 overlay.dtb" ; exit 1 )
config=`mount -t configfs | awk '{ print $3 }'`
name=`basename $1`
dir=$config/device-tree/overlays/$name
test -d $dir && rmdir $dir
mkdir $dir
cat $dtb > $dir/dtbo
cat $dir/status
