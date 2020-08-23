#!/bin/sh -e

dtb=$1
test -f "$dtb" || ( echo "Usage: $0 overlay.dtb" ; exit 1 )

if echo $dtb | grep '\.dts$' ; then
	echo "Compile overlay $dtb"
	dtc -I dts -O dtb -o $dtb.dtb $dtb
	dtb=$dtb.dtb
	echo "Created $dtb"
fi

config=`mount -t configfs | awk '{ print $3 }'`
name=`basename $1`

dir=$config/device-tree/overlays/$name

# remote overlay to reaload it
test -d $dir && rmdir $dir

mkdir $dir
cat $dtb > $dir/dtbo
cat $dir/status

echo "Remove with: rmdir $dir"
