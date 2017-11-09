#!/usr/bin/perl
use warnings;
use strict;
use autodie;
use Data::Dump qw(dump);
use Getopt::Long;

my $opt_svg = $ENV{SVG} || 0;
my $opt_alt = $ENV{ALT} || 0;
my $opt_invert = $ENV{INVERT} = 0;
my $opt_vertical = $ENV{VERTICAL} = 0;
my $opt_kernel = $ENV{kernel} = 1;
GetOptions(
	'svg!' => \$opt_svg,
	'alt!' => \$opt_alt,
	'invert!' => \$opt_invert,
	'vertical!' => \$opt_vertical,
	'kernel!' => \$opt_kernel,
);

# svg font hints
my $font_w = 1.67; # < 2.54, font is not perfect square

my $txt_color = '#000000';
   $txt_color = '#ffffff' if $opt_invert;

sub slurp {
	open(my $fh, '<', shift);
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
	if ( m/^#\s*$model/ ) {
		$include = 1;
	} elsif ( m/^#\s+/ ) {
		$include = 0;
	} elsif ( $include ) {
		push @{ $pins->{$1} }, $line_i while ( m/\t(P\w\d+)/g );

		push @lines, $_;

		$line_i++;
	} else {
		warn "IGNORE: [$_]\n";
	}
}

die "add pin definition for # $model" unless $pins;

warn "# pins ",dump($pins);

my $pin_function;

open(my $fh, '<', '/sys/kernel/debug/pinctrl/pinctrl-handles');
while(<$fh>) {
	chomp;
	if ( m/group: (P\w\d+)\s.+function: (\S+)/ ) {
		my ($pin, $function) = ($1,$2);
		$pin_function->{$pin} = $function;

		next unless $opt_kernel;

		if ( $pins->{$pin} ) {
			foreach my $line ( @{$pins->{$pin}} ) {
warn "XXX $pin $line";
				my $t = $lines[$line];
				if ( $opt_svg ) {
					$t =~ s/$pin/[$function]/;
				} else {
					$t =~ s/$pin/$pin [$function]/ || die "can't find $pin in [$t]";
				}
				$lines[$line] = $t;
				warn "# $line: $lines[$line]\n";
			}
		} else {
			warn "IGNORED: pin $pin function $function\n";
		}
	}
}

my @max_len = ( 0,0,0,0 );
my @line_parts;
foreach my $line (@lines) {
	if ( $line =~ m/^#/ ) {
		push @line_parts, [ $line ] unless $opt_svg;
		next;
	}
	$line =~ s/\s*\([^\)]+\)//g if ! $opt_alt;

	my @v = split(/\s*\t+\s*/,$line,4);
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

my $fmt = "%$max_len[0]s %-$max_len[1]s %$max_len[2]s %-$max_len[3]s\n";

my $x = 30.00; # mm
my $y = 30.00; # mm

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
	i2c  => [ '#008888', '#ffcccc' ],
	uart => [ '#880088', '#ccffcc' ],
	spi  => [ '#888800', '#ccccff' ],
};

sub svg_style {
	my ($name,$x,$y,$col) = @_;
	$y -= 2.10; # shift box overlay to right vertical position based on font baseline

	sub rect {
		my ($x,$y,$col,$fill) = @_;
    		print qq{<rect x="$x" y="$y" height="2.54" width="}, $max_len[$col] * $font_w, qq{" style="opacity:1;fill:$fill;fill-opacity:1;stroke:#ffffff;stroke-width:0.10;stroke-opacity:1" />};

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

	if ( $name =~ m/(VCC|3V3|3.3V)/i ) {
		my ($fg,$bg) = @{ $cols->{vcc} };
    		rect $x,$y,$col,$bg;
		return qq{ style="fill:$fg"};
	} elsif ( $name =~ m/(G(ND|Round)|VSS)/i ) {
		my ($fg,$bg) = @{ $cols->{gnd} };
    		rect $x,$y,$col,$bg;
		return qq{ style="fill:$fg"};
	} elsif ( $name =~ m/\[(\w+)\d\]/ ) { # kernel
		my $dev = $1;
		if ( my ($fg,$bg) = @{ $cols->{$dev} } ) {
			rect $x,$y,$col,$bg;
			return qq{ style="fill:$fg"};
		}
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

@cols_order = ( 0,1,3,2 ); # pins outside on the right
@cols_align = ( '','-','-','' );

foreach my $i ( 0 .. $#line_parts ) {
	$i = $#line_parts - $i if $opt_vertical;
	my $line = $line_parts[$i];

	my $pin_color = $alt_col ? '#cccccc' : '#444444';
	$alt_col = ! $alt_col;

	if ( $opt_svg ) {

		my ($fg,$bg) = @{ $cols->{txt} };
		my $tspan = qq{<tspan x="$x" y="$y" style="line-height:2.54;fill-opacity:1;fill:$fg;stroke:none;">};

		my $x_pos = $x;
		foreach my $i ( @cols_order ) {
			next unless $line->[$i];
			$tspan .= qq{<tspan x="$x_pos"}.svg_style($line->[$i],$x_pos,$y,$i).sprintf( '>%' . $cols_align[$i] . $max_len[$i] . 's</tspan>', $line->[$i]);
			$x_pos += $max_len[$i] * $font_w;
		}

		$tspan .= qq{</tspan>};
		push @later,sprintf $tspan, @$line;
		$y += 2.54;

		# swap pin colors for line stripes
		foreach my $swap (qw( pins txt )) {
			my ( $c1, $c2 ) = @{ $cols->{$swap} };
			$cols->{$swap} = [ $c2, $c1 ];
		};

	} else {

		if ( $#$line == 0 ) {
			print $line->[0], "\n";
		} else {
			push @$line, '' while ($#$line < 3); # fill-in single row header
			printf $fmt, @$line;
		}

	}
}

if ( $opt_svg ) {
	print qq{
    <text
       id="text4506"
       y="$x"
       x="$y"
       style="font-size:2.34px;line-height:2.54px;font-family:'Andale Mono';fill-opacity:1;stroke:none;stroke-width:0.10;stroke-opacity:1"
       xml:space="preserve">

	}; #svg

	print @later, qq{
</text>
</g>
</svg>
	}; #svg

}

__DATA__
# Cubietech Cubieboard2
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

# Cubietech Cubieboard2
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
