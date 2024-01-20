#!/usr/bin/perl
use warnings;
use strict;
use autodie;

use Data::Dump qw(dump);

my $opt_verbose = $ENV{V} || 0;
$opt_verbose = 1 if @ARGV;

my $debug = $ENV{DEBUG} || 0;

my $device; # id

open(my $lsusb, '-|', 'lsusb');
while(<$lsusb>) {
	chomp;

	if ( m/Device *(\d+): ID (.+)/ ) {
		$device->{$1 * 1} = $2;
	}

	#print "# $_\n";

}

warn "## device = ",dump($device) if $debug;

my $usb_path_tty;

foreach my $path ( glob '/dev/serial/by-path/*' ) {
	my $tty = readlink $path;
	$tty =~ s/^[\.\/]*//;
	print "# $path -> $tty\n" if $debug;
	$path =~ s/^.*-usb\w*-\d+://;
	$path =~ s/:.+$//;
	#$path =~ s/:\d+\.(\d).*$/:$1/ || die "can't keep :interface in [$path]";
	$usb_path_tty->{$path} = $tty;
}
warn "## usb_path_tty = ",dump($usb_path_tty) if $debug;

my $path = 'XXXXXX';
my @path;

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
	my $if = '';
	if ( m/Bus (\d+)\.Port (\d+): Dev (\d+), (.+)/ ) {
		$bus  = $1;
		$port = $2;
		$dev  = $3;
		@more = split(/,\s+/, $4);
	} elsif ( m/(\s+).*Port (\d+): Dev (\d+), If (\d+), (.+)/ ) {
		$level = length($1) / 4;
		$port = $2;
		$dev = $3;
		$if = $4;
		@more = split(/,\s+/, $5);
	} else {
		print "# SKIP: $_\n";
		next;
	}

	# convert to int
	$bus  = $bus * 1 if $bus;
	$port = $port * 1;
	$dev  = $dev * 1;

	@more = grep { ! m/Class=Vendor Specific Class/ } @more; # remote uninformative class

	my $speed = pop @more;

	$bus = $1 if m/Bus (\d+)/;

	@path = splice @path, 0, $level-1; push @path, $port;
	my $path = join('.', @path);

	if ( exists $usb_path_tty->{ $path } ) {
		$tty = "/dev/" . $usb_path_tty->{ $path };
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

	$o .= "[$path]" if $debug;

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
