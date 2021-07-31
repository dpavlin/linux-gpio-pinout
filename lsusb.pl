#!/usr/bin/perl
use warnings;
use strict;
use autodie;

use Data::Dump qw(dump);

my $opt_verbose = $ENV{V} || 1;
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

	my $tty;

	my @more;
	my $level = 0; # 0=bus
	my $bus;
	my $port;
	my $dev;
	my $if;
	if ( m/Bus (\d+)\.Port (\d+): Dev (\d+), (.+)/ ) {
		$bus  = $1;
		$port = $2;
		$dev  = $3;
		@more = split(/,\s+/, $4);
	} elsif ( m/(\s+).*Port (\d+): Dev (\d+), If (\d+), (.+)/ ) {
		$level = length($1) / 4;
		$port = $2;
		$dev = $3 * 1;
		$if = $4;
		@more = split(/,\s+/, $5);
	} else {
		print "# SKIP: $_\n";
		next;
	}

	my $speed = pop @more;

	$bus = $1 if m/Bus (\d+)/;

	$path = substr($path,0,$level * 2) . '.' . $port;

	#warn "### level=$level port=$2 path $path | $_\n";
	if ( length($path) > 3 && exists $usb_path_tty->{ substr($path,3) } ) {
		$tty = "/dev/" . $usb_path_tty->{ substr($path,3) };
	}


	if ( $opt_verbose > 0 ) {

		open(my $lsusb_v, '-|', "sudo lsusb -v -s $dev 2>/dev/null");
		while(<$lsusb_v>) {
			#warn "## $_\n";
			if ( m/^\s+(iManufacturer|iProduct|iSerial)\s+\S+\s+(.+)/ ) {
				push @more, "$1=$2";
			}
		}
		close($lsusb_v);

	}

	my $o;

	if ( $bus ) {
		$o = sprintf "Bus %02d Port %d, Dev %d",
			$bus, $port, $dev,
		;
	} else {
		$o = sprintf "%sPort %d, Dev %d, If %d",
			" " x ( $level * 2 ),
			$port, $dev, $if
		;
	};

	print $o;
	$o = 32 - length($o);

	#print "level=$level";
	my $name = $device->{ $dev } || die "can't find $dev in ",dump($device);
	my ($vendor_product, $name_only ) = split(/\s/,$name,2);
	printf "%${o}s ", $speed;
	print $vendor_product, " ";
	print $tty, " " if $tty;
	print $name_only, " | ";
	print join(", ", @more);

	#printf "path=%10s", $path;

	print "\n";

}
