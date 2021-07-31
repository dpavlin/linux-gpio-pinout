#!/usr/bin/perl
use warnings;
use strict;
use autodie;

use Data::Dump qw(dump);

my $opt_verbose = $ENV{V} || 0;
$opt_verbose = 1 if @ARGV;

my $device; # id

open(my $lsusb, '-|', 'lsusb');
while(<$lsusb>) {
	chomp;

	if ( m/Device *(\d+): ID (.+)/ ) {
		$device->{$1 * 1} = $2;
	}

	#print "# $_\n";

}

#warn "## device = ",dump($device);

my $usb_path_tty;

foreach my $path ( glob '/dev/serial/by-path/*' ) {
	my $tty = readlink $path;
	$tty =~ s/^[\.\/]*//;
	#print "# $path -> $tty\n";
	$path =~ s/^.*-usb-\d+://;

	#$path =~ s/:(\d).+$/:$1/; # keep :interface
	#$usb_path_tty->{$path} = $tty;

	$path =~ s/:.+$//; # without :interface
	$usb_path_tty->{$path} = $tty;
}
#warn "## usb_path_tty = ",dump($usb_path_tty);

my $path = 'XXXXXX';

open($lsusb, '-|', 'lsusb -t');
while(<$lsusb>) {
	chomp;
	#warn "# $_\n";

	my $tty = "\t";

	if ( m/(\s+)\Q|__ Port \E(\d+): Dev (\d+), If (\d+)/ ) {
		my $dev_nr = $2 * 1;
		my $if = $4;
		my $level = length($1) / 4;
		#$path = substr($path,0,$level * 2) . '.' . $2 . ':' . $if;
		$path = substr($path,0,$level * 2) . '.' . $2;
		#warn "### level=$level port=$2 path $path | $_\n";
		if ( exists $usb_path_tty->{ substr($path,3) } ) {
			$tty = " /dev/" . $usb_path_tty->{ substr($path,3) } . "\t";
		}
		#print "$path:$if";
	}

	if ( m/Dev (\d+),/ && exists $device->{ $1 * 1 } ) {
		my $dev_nr = $1 * 1;
		my $name = $device->{ $dev_nr };
		my $line = $_;
		$line =~ s/, Class=/$tty $name\tClass=/ || die "can't find $dev_nr in $_";

		if ( $opt_verbose > 0 ) {

			my $vendor_product = $name;
			$vendor_product =~ s/\s.+$//;
			my @more;
			open(my $lsusb_v, '-|', "sudo lsusb -v -d $vendor_product");
			while(<$lsusb_v>) {
				warn "## $_\n";
				if ( m/^\s+(iManufacturer|iProduct|iSerial)\s+\S+\s+(.+)/ ) {
					push @more, $2;
				}
			}
			close($lsusb_v);
			$line .= "\t" . join("\t", @more) if @more;

		}

		print "$line\n";
		#print "$_\t\t",$device->{ $1 * 1 },"\n";
	} else {
		print "# $_\n";
	}

}
