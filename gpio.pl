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
	} elsif ( $include ) {
		push @{ $pins->{$1} }, $line_i while ( m/\t(\w+\d+)/g );

		push @lines, $_;

		$line_i++;
	} else {
		warn "IGNORE: [$_]\n";
	}
}

die "add pin definition for # $model" unless $pins;

shift(@lines) while ( ! $lines[0] );	# remove empty at beginning
pop(@lines) while ( ! $lines[-1] );	# remove empty at end

warn "# pins ",dump($pins);

my $pin_function;
my $device;

open(my $fh, '<', $opt_read . '/sys/kernel/debug/pinctrl/pinctrl-handles');
while(<$fh>) {
	chomp;
	if ( m/device: [0-9a-f]+\.(\w+)/ ) {
		$device = $1;
	} elsif ( m/group: (\w+\d+)\s.+function: (\S+)/ ) {
		my ($pin, $function) = ($1,$2);
		$pin_function->{$pin} = "$device $function";

		if ( $pins->{$pin} ) {
			foreach my $line ( @{$pins->{$pin}} ) {
				my $t = $lines[$line];
				if ( $opt_svg ) {
					$t =~ s/$pin/[$device $function]/;
				} else {
					$t =~ s/$pin/$pin [$device $function]/ || die "can't find $pin in [$t]";
				}
				$lines[$line] = $t;
				warn "# $line: $lines[$line]\n";
			}
		} else {
			warn "IGNORED: pin $pin function $function\n";
		}
	}
}

warn "# pin_function = ",dump($pin_function);

my @max_len = ( 0,0,0,0 );
my @line_parts;
foreach my $line (@lines) {
	if ( $line =~ m/^#/ ) {
		push @line_parts, [ $line ] unless $opt_svg;
		next;
	}
	$line =~ s/(\[(?:uart|serial))([^\t]*\]\s[^\t]*(rx|tx)d?)/$1 $3$2/gi;
	$line =~ s/(\[i2c)([^\t]*\]\s[^\t]*(scl?k?|sda))/$1 $3$2/gi;
	$line =~ s/(\[spi)([^\t]*\]\s[^\t]*(miso|mosi|s?clk|c[se]\d*))/$1 $3$2/gi;
	$line =~ s/\s*\([^\)]+\)//g if ! $opt_alt;

	# shorten duplicate kernel device/function
	$line =~ s/\[serial (\w+) (uart\d+)\]/[$2 $1]/g;
	$line =~ s/\[(\w+) (\w+) \1(\d+)\]/[$1$3 $2]/g;

	my @v = split(/\s*\t+\s*/,$line,4);
	@v = ( $v[2], $v[3], $v[0], $v[1] ) if $opt_horizontal;

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
cut_mark $x, $y;
my $max_x = $x;
$max_x += $max_len[$_] * $font_w foreach ( 0 .. 3 );
cut_mark $max_x, $y;

sub line {
	my ($x,$y,$max_x) = @_;
	push @cut_marks, sprintf($line_fmt, $x, $y-$font_b, $max_x, $y-$font_b);
}


my $last_cut_mark = 0;

foreach my $i ( 0 .. $#line_parts ) {
	$i = $#line_parts - $i if $opt_vertical;
	my $line = $line_parts[$i];

	if ( $opt_svg ) {

		if ( ! exists $line->[0] ) {
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
			my $x2 = $x_pos + ( $max_len[$i] * $font_w ) / 2;
			$tspan .= qq{<tspan x="$x2" text-anchor="$text_anchor"}.svg_style($line->[$order],$x_pos,$y,$i).sprintf( '>%' . $cols_align[$i] . $max_len[$i] . 's</tspan>', $line->[$order]);
			$x_pos += $max_len[$i] * $font_w;
		}

		$tspan .= qq{</tspan>\n};
		push @later,sprintf $tspan, @$line;
		$y += 2.54;

		# swap pin colors for line stripe
		if ( $opt_zebra ) {
			swap_cols $_ foreach qw( pins txt );
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

__DATA__
# Cubietech Cubieboard
## U14 (Next to SATA connector)
### 	SPI0
48 	PI13 (SPI0-MISO/UART6-RX/EINT25) 	47 	PI11 (SPI0-CLK/UART5-RX/EINT23)
46 	PI12 (SPI0-MOSI/UART6-TX/EINT24) 	45 	PI10 (SPI0-CS/UART5-TX/EINT22)
###	LCD
44 	3.3V (nc in 2012-08-08) 		43 	VCC-5V
42 	Ground					41 	SPDIF
40 	PB10 (LCD0-SCK/LCD-PIO1) 		39 	PB11 (LCD0-SDA/LCD-PIO2)
38 	Ground					37 	PH7 (LCD0-BL-EN/LCD-PIO0/UART5-RX/EINT7)
36 	XN_TP (TP-X2)				35 	YN_TP (TP-Y2)
34 	XP_TP (TP-X1)				33 	YP_TP (TP-Y1)
32 	PD25 (LCDDE) 				31 	PB2 (PWM0)
30 	PD26 (LCDHSYNC/VGA-HSYNC)	 	29 	PD24 (LCDCLK)
28 	PD23 (LCDD23) 				27 	PD27 (LCDVSYNC/VGA-VSYNC)
26 	PD21 (LCDD21) 				25 	PD22 (LCDD22)
24 	PD19 (LCDD19/LVDS1N3) 			23 	PD20 (LCDD20)
22 	PD17 (LCDD17/LVDS1NC) 			21 	PD18 (LCDD18/LVDS1P3)
20 	Ground 					19 	PD16 (LCDD16/LVDS1PC)
18 	PD14 (LCDD14/LVDS1P2) 			17 	PD15 (LCDD15/LVDS1N2)
16 	PD12 (LCDD12/LVDS1P1) 			15 	PD13 (LCDD13/LVDS1N1)
14 	PD10 (LCDD10/LVDS1P0) 			13 	PD11 (LCDD11/LVDS1N0)
12 	PD8 (LCDD8/LVDS0P3) 			11 	PD9 (LCDD9/LVDS0N3)
10 	PD7 (LCDD7/LVDS0NC) 			9 	Ground
8 	PD5 (LCDD5/LVDS0N2) 			7 	PD6 (LCDD6/LVDS0PC)
6 	PD3 (LCDD3/LVDS0N1) 			5 	PD4 (LCDD4/LNVS0P2)
4 	PD1 (LCDD1/LVDS0N0) 			3 	PD2 (LCDD2/LVDS0P1)
2 	Ground 					1 	PD0 (LCDD0/LVDSP0)

## U15 (Between Ethernet port and USB ports)
### CSI1/TS
1 	VCC-5V 					2 	PH15 (CSI1-PWR/EINT15)
3 	CSI1-IO-2V8				4 	PH14 (CSI1-RST#/EINT14)
5 	PG0 (CSI1-PCLK/SDC1-CMD) 		6 	PB18 (TWI1-SCK)
7 	PB19 (TWI1-SDA) 			8 	PG3 (CSI1-VSYNC/SDC1-D1)
9 	PG2 (CSI1-HSYNC/SDC1-D0) 		10 	PG1 (CSI1-MCLK/SDC1-CLK)
11 	PG4 (CSI1-D0/SDC1-D2) 			12 	PG5 (CSI1-D1/SDC1-D3)
13 	PG6 (CSI1-D2/UART3-TX) 			14 	PG7 (CSI1-D3/UART3-RX)
15 	PG8 (CSI1-D4/UART3-RTS) 		16 	PG9 (CSI1-D5/UART3-CTS)
17 	PG10 (CSI1-D6/UART4-TX) 		18 	PG11 (CSI1-D7/UART4-RX)
19 	Ground 					20 	Ground
###  	Analog SDIO3
21 	FMINL 					22 	PI4 (SDC3-CMD)
23 	FMINR 					24 	PI5 (SDC3-CLK)
25 	Ground 					26 	PI6 (SDC3-D0)
27 	VGA-R 					28 	PI7 (SDC3-D1)
29 	VGA-G 					30 	PI8 (SDC3-D2)
31 	VGA-B 					32 	PI9 (SDC3-D3)
###  	CSI0/TS
33 	LCD1-VSYNC 				34 	PE4 (CSI0-D0)
35 	LCD1-HSYNC 				36 	PE5 (CSI0-D1)
37 	Ground 					38 	PE6 (CSI0-D2)
39 	AVCC 					40 	PE7 (CSI0-D3)
41 	LRADC0 					42 	PE8 (CSI0-D4)
43 	CVBS 					44 	PE9 (CSI0-D5)
45 	HPL 					46 	PE10 (CSI0-D6)
47 	HPR 					48 	PE11 (CSI0-D7)

## DEBUG serial (middle of board)
4	PB22 (UART0-TX)
3	PB23 (UART0-RX)
2	VCC-3V3
1	GND


# Lamobo R1
## CON3 rpi DIP26-254
1	3.3v			2	5v     
3	PB20 SDA.1		4	5V     
5	PB21 SCL.1		6	0v     
7	PI3 PWM1		8	PH0 UART3_TX
9	0v			10	PH1 UART3_RX
11	PI19 UART2_RX		12	PH2
13	PI18 UART2_TX		14	0v     
15	PI17 UART2_CTS		16	PH21 CAN_RX 
17	3.3v			18	PH20 CAN_TX 
19	PI12 SPI0_MOSI		20	0v     
21	PI13 SPI0_MISO		22	PI16 UART2_RTS   
23	PI11 SPI0_SCLK		24	PI10 SPI0_CS0    
25	0v			26	PI14 SPI0_CS1

## J13 DIP2-254
2	PB22 UART0_TX
1	PB23 UART0_RX

## J12 DIP8-254
8	GND			7	GND
6	PI20 UART7_TX		5	PH3
4	PI21 UART7_RX		3	PH5
2	3V3			1	SATA-5V

# Raspberry Pi
1	3.3v			2 	5v
3	gpio2 (SDA.1)		4 	5v
5	gpio3 (SCL.1)		6 	0v
7	gpio4 (WPi 7)		8 	gpio14  (TxD)
9	0v			10	gpio15  (RxD)
11	gpio17 (WPi 0)		12	gpio18  (WPi 1)
13	gpio27 (WPi 2)		14	0v
15	gpio22 (WPi 3)		16	gpio23  (WPi 4)
17	3.3v			18	gpio24  (WPi 5)
19	gpio10 (MOSI)		20	0v
21	gpio9 (MISO)		22	gpio25  (WPi 6) 
23	gpio11 (SCLK)		24	gpio8   (CE0)
25	0v			26	gpio7   (CE1)
# Raspberry Pi 3 Model B Rev 1.2
27	gpio0 (SDA.0)		28	gpio1   (SCL.0)
29	gpio5 (WPi 21)		30	0v
31	gpio6 (WPi 22)		32	gpio12  (WPi 26)
33	gpio13 (WPi 23)		34	0v
35	gpio19 (WPi 24)		36	gpio16  (WPi 27)
37	gpio26 (WPi 25)		38	gpio20  (WPi 28)
39	0v			40	gpio21  (WPi 29)

