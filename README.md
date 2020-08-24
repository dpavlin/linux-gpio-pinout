# linux-gpio-pinout

`gpio.pl` will lookup kernel's view of pinouts on different boards (useful for device tree and gpio debugging)

To install dependencies, run `debian-install.sh`

It needs `root` privileges, and generates wide aligned output, so it's probably best to run it like this:

	sudo ./gpio.pl | less -S

Layout of pins is described using files in [pins](pins/) directory. File used is determined on the
runtime device tree name found in `/proc/device-tree/model` with optional `.txt` extension.
Filenames can be just beginning of this value to support mutiple models with same file.

Lines starting with `#` are regex to select pinout based on `/proc/device-tree/model` and it will
not be included in output. Good example is [pins/Raspberry Pi.txt](pins/Raspberry%20Pi.txt) which
defines pinouts of all Rasperry Pis without duplication.

Lines with `##` are descriptions or comments (name of header, for example) which will be included
in output.

One or two row pin headers (separated by a tab) are supported, and 2.54mm pin spacing is assumed.

First value (separated by spaces) specifies the name of pin as shown on board, while the second 
value specifies kernel gpio (eg. `gpio 42`) and an optional description, usually in round brackets. 
It can include additional spaces, but not tabs, since a tab specifies second column.

`--pinmux` flag will include kernel's view of available pin muxing confiration
in curly braces `{}`. This is useful to find pins which are interrupt capable.

`--alt` flag will use round braces `()` data from pins file and `raspi-gpio funcs` to produce
readable possible pin configurations.

To support breakout boards with different pinouts, you can use `--pins` argument:

	sudo ./gpio.pl --pins pins/Raspberry\ Pi-Extension\ Board.txt



It will dump a lot of output to `STDERR` which can also be useful for debugging or examining kernel's
view of your system.

`gpio.pl` tool will also create SVG pinouts if you invoke it with `--svg` argumet. Output will have 
correct 2.54mm spacing so you can put it on your board to make wiring it up easier:

	sudo ./gpio.pl --svg pins/Raspberry\ Pi.txt > /tmp/rpi.svg


## device tree

For device tree information, best source right now is this presentation:
https://elinux.org/images/d/dc/Elce_2017_dt_bof.pdf


[device-tree](device-tree/) directory contains example device trees.

To load them on runtime, use `overlay-load.sh` like this:

	vi device-tree/gpio-leds.dts
	armbian-add-overlay device-tree/gpio-led.dts
	dmesg -w &
	./overlay-load.sh /boot/overlay-user/gpio-led.dtbo

If you are not using armbian, you can also specify dts file which
will compile it for you:

	pi@pihdmi:~/linux-gpio-pinout/device-tree $ sudo ../overlay-load.sh rpi_control_board.dts

## i2c

To load kernel module for i2c sensors without writing device tree
echo module_name address into i2c bus:

	echo lm75 0x49 > /sys/bus/i2c/devices/i2c-1/new_device



[i2c-userspace](i2c-userspace/) contains random i2c userspace device drivers

`i2c-tracing.sh` is script which shows example how to use i2c tracing. This
is software-only alternative to logic analyzer if you are debugging i2c
communication.


## device tree compiler

For overlay to work on 4.17 kernels you need recent dtc compiler from:

	git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git

which in turn needs bison and flex to compile:

	apt-get install bison flex

type make to compile it and create symlink to it:

	dpavlin@cubieboard2:~/linux-gpio-pinout/dtc$ sudo ln -sfv `pwd`/dtc /lib/modules/$(uname -r)/build/scripts/dtc/dtc


For 64-bit sunxi (like Pine64) sunxi-tools doesn't show all ports (up to PL), so I included script to
compile it from source with a fix:

	dpavlin@pine64:~/linux-gpio-pinout$ ./sunxi-tools-sunxi64-install.sh 

