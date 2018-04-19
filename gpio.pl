#!/usr/bin/perl
use warnings;
use strict;
use autodie;
use Data::Dump qw(dump);
use Getopt::Long;

my $opt_svg = 0;
my $opt_alt = 0;
my $opt_invert = 0;
my $opt_vertical = 0;
my $opt_horizontal = 0;
my $opt_edge = 0;
my $opt_middle = 0;
my $opt_zebra = 0;
my $opt_lines = 0;
my $opt_read = '';
my $opt_pins = '';
my $opt_color = 0;
my $opt_pinmux = 0;
GetOptions(
	'svg!' => \$opt_svg,
	'alt!' => \$opt_alt,
	'invert!' => \$opt_invert,
	'vertical-flip!' => \$opt_vertical,
	'horizontal-flip!' => \$opt_horizontal,
	'edge-pins!' => \$opt_edge,
	'middle-pins!' => \$opt_middle,
	'zebra!' => \$opt_zebra,
	'lines!' => \$opt_lines,
	'read=s' => \$opt_read,
	'pins=s' => \$opt_pins,
	'color' => \$opt_color,
	'pinmux' => \$opt_pinmux,
);

# svg font hints
my $font_w = 1.67; # < 2.54, font is not perfect square
my $font_b = 2.10; # font baseline position

$opt_read .= '/' unless $opt_read =~ m/\/$/;

sub slurp {
	open(my $fh, '<', $opt_read . shift);
	local $/ = undef;
	<$fh>;
}

my $pins;

my $model = slurp('/proc/device-tree/model');
$model =~ s/\x00$//; # strip kernel NULL
warn "# model [$model]";

OPEN_PINS_AGAIN:
open(DATA, '<', $opt_pins) if $opt_pins;

my @lines;
my $line_i = 0;

my $include = 0;
while(<DATA>) {
	chomp;
	if ( m/^#\s(.+)/ ) {
		warn "MODEL [$1] == [$model] ?\n";
		if ( $model =~ m/$1/ ) {
			$include = 1;
		} else {
			$include = 0;
		}
	} elsif ( $include || $opt_pins ) {
		push @{ $pins->{$1} }, $line_i while ( m/\t\s*(\w+\d+)/g );

		push @lines, $_;

		$line_i++;
	} else {
		warn "IGNORE: [$_]\n";
	}
}

if ( ! $opt_pins && ! $pins ) {
	my $glob = $model;
	$glob =~ s/^(\w+).*$/$1/;
	my @pins = glob "pins/${glob}*";
	warn "# possible pins: ",dump( \@pins );
	$opt_pins = $pins[0];
	goto OPEN_PINS_AGAIN;
}

die "add pin definition for # $model" unless $pins;

#warn "# lines ",dump( \@lines );
warn "# pins ",dump($pins);

my $serial_tty;
foreach (
	glob($opt_read . '/sys/devices/platform/soc*/*.serial/tty/tty*'),	# 4.x
	glob(            '/sys/devices/soc.*/*.uart/tty/tty*')			# 3.10
) {
	my @v = split(/\//, $_);
	$serial_tty->{ $v[-3] } = $v[-1];
}
warn "# serial_tty = ",dump($serial_tty);


my $pin_function;
my $device;
my $pin;
my $function;

sub annotate_pin {
	my ($pin, $note) = @_;
	if ( $pins->{$pin} ) {
		foreach my $line ( @{$pins->{$pin}} ) {
			my $t = $lines[$line];
			if ( $opt_svg ) {
				$t =~ s/$pin/$note/;
			} else {
				$t =~ s/$pin/$pin $note/ || warn "can't find $pin in [$t]";
			}
			$lines[$line] = $t;
			warn "# $line: $lines[$line]\n";
		}
	} else {
		warn "IGNORED: pin $pin function $note\n";
	}
}

open(my $fh, '<', $opt_read . '/sys/kernel/debug/pinctrl/pinctrl-maps');
while(<$fh>) {
	chomp;
	if ( m/^device (\S+)/ ) {
		$device = $1;
		if ( my $replace = $serial_tty->{$device} ) {
			$device = $replace; # replace serial hex with kernel name
		} else {
			$device =~ s/^[0-9a-f]*\.//; # remove hex address
		}
	} elsif ( m/^group (\w+\d+)/ ) {
		$pin = $1;

	} elsif ( m/^function (\S+)/ ) {
		$function = $1;
	} elsif ( m/^$/ ) {
		if ( $device && $pin && $function ) {
			push @{ $pin_function->{$pin} }, "$device $function";

			annotate_pin $pin, "[$device $function]";
		} else {
			warn "missing one of ",dump( $device, $pin, $function );
		}

		$device = undef;
		$pin = undef;
		$function = undef;

	}
}

warn "# pin_function = ",dump($pin_function);


# insert kernel gpio info
my $linux_gpio_name;
open(my $pins_fh, '<', (glob "/sys/kernel/debug/pinctrl/*/pins")[0]);
while(<$pins_fh>) {
	if ( m/^pin (\d+) \(([^\)]+)\)/ ) {
		$linux_gpio_name->{$1} = $2;
	}
}
warn "# linux_gpio_name = ",dump( $linux_gpio_name );


my $gpio_debug;
open(my $gpio_fh, '<', '/sys/kernel/debug/gpio');
while(<$gpio_fh>) {
	if (m/|/ ) {
		s/^\s+//;
		s/\s+$//;
		my @l = split(/\s*[\(\|\)]\s*/, $_);
		warn "XXX ", dump( \@l );
		if ( $l[0] =~ m/gpio-(\d+)/ ) {
			if ( my $pin = $linux_gpio_name->{$1} ) {
				$gpio_debug->{ $pin } = $l[2];
				$l[3] =~ s/\s\s+/ /g;
				annotate_pin $pin, qq{"$l[2]" $l[3]};
			} else {
				warn "FIXME can't find $1 in ",dump( $linux_gpio_name );
			}
		}
	}

}
warn "# gpio_debug = ",dump( $gpio_debug );



my $have_sunxi_pio = `which sunxi-pio`;
if ( $have_sunxi_pio ) {

open(my $pio, '-|', 'sunxi-pio -m print');
while(<$pio>) {
	chomp;
	s/[<>]+/ /g;
	my @p = split(/\s+/,$_);
	warn "# pio ",dump(\@p);
	# annotate input 0 and output 1 pins
#	annotate_pin $p[0], ( $p[1] ? 'O' : 'I' ) . ':' . $p[4] if $p[1] == 0 || $p[1] == 1;
	my $pin = shift @p;
	annotate_pin $pin, join(' ',@p) if ! $opt_svg;
}
close($pio);

} # have_sunxi_pio

my $have_raspi_gpio = `which raspi-gpio`;
if ( $have_raspi_gpio ) {

my @gpio_pins;

open(my $pio, '-|', 'raspi-gpio get');
while(<$pio>) {
	chomp;
	if ( m/^\s*GPIO (\d+): (.+)/ ) {
		my $pin = 'gpio' . $1;
		push @gpio_pins, $1;
		annotate_pin $pin, $2 if ! $opt_svg;
	}
}
close($pio);

open(my $pio, '-|', 'raspi-gpio funcs '.join(',',@gpio_pins));
while(<$pio>) {
	chomp;
	s/,\s/ /g;
	if (m/^(\d+)\s+(.*)/) {
		annotate_pin 'gpio'.$1,"($2)" if $opt_alt;
	}
}
close($pio);

} # have_raspi_gpio


my $pinmux;
my $pinmux_path = (glob("/sys/kernel/debug/pinctrl/*/pinmux-functions"))[0];
if ( $opt_pinmux && -e $pinmux_path ) {
	open(my $mux, '<', $pinmux_path);
	while(<$mux>) {
		chomp;
		if ( m/function: (\w+), groups = \[ (.*) \]/ ) {
			my ( $func, $pins ) = ( $1, $2 );
			foreach ( split(/\s+/,$pins) ) {
				push @{ $pinmux->{$_} }, $func;
			}
		} else {
			warn "IGNORED [$pinmux_path] [$_]\n";
		}
	}

	foreach my $pin ( keys %$pinmux ) {
		if ( exists $pins->{$pin} ) {
			annotate_pin $pin, '{' . join(' ', @{$pinmux->{$pin}}) . '}';
		} else {
			warn "IGNORED mux on $pin\n";
		}
	}

	warn "# pinmux = ",dump( $pinmux );
}



my @max_len = ( 0,0,0,0 );
my @line_parts;

shift(@lines) while ( ! $lines[0] );	# remove empty at beginning
pop(@lines) while ( ! $lines[-1] );	# remove empty at end

foreach my $line (@lines) {
	if ( $line =~ m/^#/ ) {
		push @line_parts, [ $line ] unless $opt_svg && $line =~ m/^###+/; # SVG doesn't display 3rd level comments
		next;
	}
	$line =~ s/\[(\w+)\s+(\w+)\] \[\1\s+(\w+)\]/[$1 $2 $3]/g; # compress kernel annotation with same prefix
	$line =~ s/(\[(?:uart\d*|serial|tty\w+))([^\t]*\]\s[^\t]*(rx|tx)d?)/$1 $3$2/gi;
	$line =~ s/(\[i2c)([^\t]*\]\s[^\t]*(scl?k?|sda))/$1 $3$2/gi;
	$line =~ s/(\[spi)([^\t]*\]\s[^\t]*(miso|mosi|s?clk|c[se]\d*))/$1 $3$2/gi;
	$line =~ s/\s*\([^\)]+\)//g if ! $opt_alt;

	# shorten duplicate kernel device/function
	$line =~ s/\[serial (\w+) (uart\d+)\]/[$2 $1]/g;
	$line =~ s/\[(\w+) (\w+) \1(\d+)\]/[$1$3 $2]/g;

	$line =~ s/\[(\w+)\s+([^\]]+)\s+\1\]/[$1 $2]/g;	# duplicate

	my @v = split(/\s*\t+\s*/,$line,4);
	@v = ( $v[2], $v[3], $v[0], $v[1] ) if $opt_horizontal && $v[2];

	push @line_parts, [ @v ];
	foreach my $i ( 0 .. 3 ) {
		next unless exists $v[$i];
		next if $v[$i] =~ m/^#/; # don't calculate comments into max length
		my $l = length($v[$i]);
		$max_len[$i] = $l if $l > $max_len[$i];
	}
}

warn "# max_len = ",dump( \@max_len );
warn "# line_parts = ",dump( \@line_parts );

#print "$_\n" foreach @lines;

my $x = 20.00; # mm
my $y = 20.00; # mm

if ( $opt_svg ) {
	print qq{<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
   xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmlns:cc="http://creativecommons.org/ns#"
   xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns="http://www.w3.org/2000/svg"
   xmlns:xlink="http://www.w3.org/1999/xlink"
   id="svg8"
   version="1.1"
   viewBox="0 0 210 297"
   height="297mm"
   width="210mm">


<g id="layer1">

	}; # svg, insert rest of rect

	print qq{<rect x="0" y="0" width="210" height="297" style="fill:#000000" id="high-contrast"/>} if $opt_invert;
}

my @later;

my $cols = {	# foreground background
	txt  => [ '#000000', '#ffffff' ],
	pins => [ '#ffffff', '#ff00ff' ],
	vcc  => [ '#ff0000', '#ffff00' ],
	gnd  => [ '#000000', '#00ffff' ],
	i2c  => [ '#008800', '#ffcccc' ],
	serial=>[ '#000088', '#ccffcc' ],
	spi  => [ '#880000', '#ccccff' ],
};

sub swap_cols {
	my $swap = shift;
	die "$swap not found in ",dump($cols) unless $cols->{$swap};
	my ( $c1, $c2 ) = @{ $cols->{$swap} };
	$cols->{$swap} = [ $c2, $c1 ];
}

swap_cols 'txt' if $opt_invert;
	

sub svg_style {
	my ($name,$x,$y,$col) = @_;

	return '' unless $opt_color;

	$y -= $font_b; # shift box overlay to right vertical position based on font baseline

	sub rect {
		my ($x,$y,$col,$fill) = @_;
    		print qq{<rect x="$x" y="$y" height="2.54" width="}, $max_len[$col] * $font_w, qq{" style="fill:$fill;stroke:#ffffff;stroke-width:0.10" />\n};

	}

	if ( $name =~ m/^(\d+)$/ ) { # pins
		my $pin = $1;
		my ( $fg, $bg ) = @{ $cols->{pins} };
		if ( $pin == 1 ) {
			my $w  = $max_len[$col]*$font_w - 0.1;
			my $cx = $x + $w;
			my $cy = $y + 2.54;
			#print qq{<polygon points="$x,$y $cx,$y $x,$cy $x,$y" stroke="$fg" stroke-width="0.25" fill="$bg" />};
			#print qq{<polygon points="$x,$cy $cx,$cy $cx,$y $x,$cy" stroke="$bg" stroke-width="0.25" fill="$fg" />};
			print qq{<rect x="$x" y="$y" width="$w" height="2.54" stroke="$fg" stroke-width="0.3" fill="$bg" />};
			my ( $fg, $bg ) = @{ $cols->{txt} };
			print qq{<rect x="$x" y="$y" width="$w" height="2.54" rx="1" ry="1" stroke="$fg" stroke-width="0.3" fill="$bg" />};
		} else {
			rect $x,$y,$col,$fg;
		}
		return qq{ style="fill:$bg"};
	}

	if ( $name =~ m/(VCC|3V3|3.3V|5v)/i ) {
		my ($fg,$bg) = @{ $cols->{vcc} };
    		rect $x,$y,$col,$bg;
		return qq{ style="fill:$fg"};
	} elsif ( $name =~ m/(G(ND|Round)|VSS|0v)/i ) {
		my ($fg,$bg) = @{ $cols->{gnd} };
    		rect $x,$y,$col,$bg;
		return qq{ style="fill:$fg"};
	} elsif ( $name =~ m/\[(\w+)/ ) { # kernel
		my $dev = $1;
		my ($fg,$bg) = @{ $cols->{txt} };
		$dev = 'serial' if $dev =~ m/^tty/;
		($fg,$bg) = @{ $cols->{$dev} } if exists $cols->{$dev};
		rect $x,$y,$col,$bg;
		return qq{ style="fill:$fg"};
	} else {
		my ( $fg, $bg ) = @{ $cols->{txt} };
    		rect $x,$y,$col,$bg;
		#return qq{ style="fill:$fg"};
		return '';
	}
}

my $alt_col = 0;

my @cols_order = ( 0,1,2,3 );
my @cols_align = ( '','-','','-' ); # sprintf prefix

my @cols_shuffle = @cols_order;

if ( $opt_edge ) {
	# pins outside on the right
	@cols_shuffle = ( 0,1,3,2 ) if $opt_edge;
	@cols_align = ( '-','-','','' );
} elsif ( $opt_middle ) {
	# pins in middle
	@cols_shuffle = ( 1,0,2,3 );
	@cols_align = ( '','','-','-' );
}

sub cols_shuffle {
	my ( $what, $order ) = @_;
	my $new = [];
	foreach my $i ( 0 .. $#$what ) {
		$new->[$i] = $what->[ $order->[$i] ];
	}
	warn "# cols_shuffle what=",dump($what)," order=",dump($order)," new=",dump($new);
	return @$new;
}

@cols_order = cols_shuffle( \@cols_order, \@cols_shuffle );
@max_len    = cols_shuffle( \@max_len,    \@cols_shuffle );

warn "# cols_order = ",dump( \@cols_order );
warn "# cols_align = ",dump( \@cols_align );

my $fmt = "%$cols_align[0]$max_len[0]s %$cols_align[1]$max_len[1]s %$cols_align[2]$max_len[2]s %$cols_align[3]$max_len[3]s\n";


# cut marks
my ($fg,$bg) = @{ $cols->{txt} };
my $line_fmt = qq{<line x1="%s" y1="%s" x2="%s" y2="%s" style="stroke:$fg;stroke-width:0.10;fill:$bg" />\n};

my @cut_marks;
sub cut_mark {
	my ($x,$y) = @_;
	return unless $opt_svg;
	push @cut_marks, sprintf($line_fmt, $x-5, $y-$font_b,   $x+5, $y-$font_b);
	push @cut_marks, sprintf($line_fmt, $x,   $y-$font_b-5, $x,   $y-$font_b+5);
}
#cut_mark $x, $y;
my $max_x = $x;
$max_x += $max_len[$_] * $font_w foreach ( 0 .. 3 );
#cut_mark $max_x, $y;

sub line {
	my ($x,$y,$max_x) = @_;
	push @cut_marks, sprintf($line_fmt, $x, $y-$font_b, $max_x, $y-$font_b);
}


my $last_cut_mark = 0;

sub connector {
	my ( $from, $to ) = @_;
	warn "# connector $from - $to ",dump( $line_parts[$from], $line_parts[$to] );
	if ( $opt_vertical ) {
		foreach my $i ( 0 .. int(($to-$from)/2) ) {
			my $t = $line_parts[$from + $i];
			        $line_parts[$from + $i] = $line_parts[$to - $i];
			                                  $line_parts[$to - $i] = $t;
		}
	}
}

my $from;
my $to;
foreach my $i ( 0 .. $#line_parts ) {
	next if $line_parts[$i]->[0] =~ m/^###/;
	if (exists $line_parts[$i]->[1]) {
		if (! $from) {
			$from = $i;
		} else {
			$to = $i;
		}
	} elsif ($from && $to) {
		connector $from => $to;
		$from = $to = undef;
	}
}
connector $from => $to if $from && $to;

foreach my $i ( 0 .. $#line_parts ) {
#	$i = $#line_parts - $i if $opt_vertical;
	my $line = $line_parts[$i];

	if ( $opt_svg ) {

		# not a minimal two column pin description
		if ( ! exists $line->[1] ) {
			$last_cut_mark = 1 if $line->[0] =~ m/^##/; # skip comments

			# before first empty line
			if ( $last_cut_mark == 0 ) {
				cut_mark $x, $y;
				cut_mark $max_x, $y;
				$last_cut_mark = 1;
				line $x, $y, $max_x if $opt_lines;
				$y += 15; # make spacing between pinouts
			}
		} elsif ( $last_cut_mark ) {
			# first full line
			cut_mark $x, $y;
			cut_mark $max_x, $y;
			$last_cut_mark = 0;
		} else {
			#warn "CUTMARK no magic";
		}

		line $x, $y, $max_x if $opt_lines && exists $line->[1];

		my ($fg,$bg) = @{ $cols->{txt} };
		my $tspan = qq{<tspan x="$x" y="$y" style="line-height:2.54;fill:$fg;stroke:none;">\n};

		my $x_pos = $x;
		foreach my $i ( 0 .. $#cols_order ) {
			my $order = $cols_order[$i];
			next unless $line->[$order];

			my $text_anchor = 'middle';
			my $len = $max_len[$i];
			my $x2 = $x_pos + ( $len * $font_w ) / 2;
			# is this comment?
			if ( $#$line == 0 && $line->[$order] =~ s/^#+s*// ) {
				# comment, center over whole width
				$len = length($line->[$order]);
				$x2 = $x + (($max_x-$x)/2); # middle
				$tspan .= qq{\t<tspan x="$x2" text-anchor="$text_anchor"}.sprintf( '>%' . $cols_align[$i] . $len . 's</tspan>', $line->[0]);
			} else {
				$tspan .= qq{\t<tspan x="$x2" text-anchor="$text_anchor"}.svg_style($line->[$order],$x_pos,$y,$i).sprintf( '>%' . $cols_align[$i] . $len . 's</tspan>', $line->[$order]);
			}
			$x_pos += $len * $font_w;
		}

		$tspan .= qq{\n</tspan>\n};
		push @later,sprintf $tspan, @$line;
		$y += 2.54;

		# swap pin colors for line stripe
		if ( $opt_zebra ) {
			swap_cols $_ foreach qw( pins txt );
		} else {
			swap_cols 'pins';
		}

	} else {

		if ( $#$line == 0 ) {
			print $line->[0], "\n";
		} else {
			push @$line, '' while ($#$line < 3); # fill-in single row header
			printf $fmt, map { $line->[$_] } @cols_order;
		}

	}
}

if ( $opt_svg ) {
	cut_mark $x,$y;
	cut_mark $max_x,$y;
	line $x, $y, $max_x if $opt_lines;

	print qq{
    <text
       id="text4506"
       y="$x"
       x="$y"
       style="font-size:2.34px;line-height:2.54px;font-family:'Andale Mono';stroke:none"
       xml:space="preserve">

	}; #svg

	print @later, qq{</text>\n}, @cut_marks, qq{</g>\n</svg>};

}

# you can add pin definitions below, but they should go into pins/
__DATA__

