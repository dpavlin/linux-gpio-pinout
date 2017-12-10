# linux-gpio-pinout

lookup kernel's view of pinouts on different boards (useful for device tree and gpio debugging)


It supports simple one or two row pin headers with 2.54mm pin spacing which are specified in
simple text form at end of file based on model derived from device tree.

This tool also creates svg pinouts which you can print out with correct 2.54mm spacing and put
on your board to make wiring easier.


For device tree information, best source right now is this presentation:
https://elinux.org/images/d/dc/Elce_2017_dt_bof.pdf


device-tree/ directory contains examples

to use device trees, do something like:

	vi device-tree/gpio-leds.dts
	armbian-add-overlay device-tree/gpio-led.dts
	dmesg -w &
	./overlay-load.sh /boot/overlay-user/gpio-led.dtbo


To load kernel module for i2c sensors without writing device tree
echo module_name address into i2c bus:

echo lm75 0x49 > /sys/bus/i2c/devices/i2c-1/new_device



i2c-usersapce/ contains random i2c userspace device drivers
