#!/bin/sh -e
#
# interactively toggle LEDs defined in kernel /sys/class/leds/
#
# readc from
# https://unix.stackexchange.com/questions/464930/can-i-read-a-single-character-from-stdin-in-posix-shell

readc() { # arg: <variable-name>
  if [ -t 0 ]; then
    # if stdin is a tty device, put it out of icanon, set min and
    # time to sane value, but don't otherwise touch other input or
    # or local settings (echo, isig, icrnl...). Take a backup of the
    # previous settings beforehand.
    saved_tty_settings=$(stty -g)
    stty -icanon min 1 time 0
  fi
  eval "$1="
  while
    # read one byte, using a work around for the fact that command
    # substitution strips the last character.
    c=$(dd bs=1 count=1 2> /dev/null; echo .)
    c=${c%.}

    # break out of the loop on empty input (eof) or if a full character
    # has been accumulated in the output variable (using "wc -m" to count
    # the number of characters).
    [ -n "$c" ] &&
      eval "$1=\${$1}"'$c
        [ "$(($(printf %s "${'"$1"'}" | wc -m)))" -eq 0 ]'; do
    continue
  done
  if [ -t 0 ]; then
    # restore settings saved earlier if stdin is a tty device.
    stty "$saved_tty_settings"
  fi
}

while true; do

grep . /sys/class/leds/*/brightness | cat -n | awk '{ if ( $1 < 10 ) print $1 " " $2; else printf "%c %s\n", $1 + 97 - 10, $2; }' | tee /dev/shm/leds

echo -n "# toggle led: "
readc LED
#echo "got [$LED]"
grep "\b$LED\b" /dev/shm/leds | while read nr rest ; do
	path=$( echo $rest | sed 's/:[0-9]*$//' )
	b=$( echo $rest | sed 's/^.*:\([0-9]*\)$/\1/' )
	m=$( cat $( echo $path | sed 's,/brightness,/max_brightness,' ) )
	echo "## $path $b $m"
	if [ $b != $m ] ; then
		echo $m > $path
	else
		echo 0 > $path
	fi
done


done # while

