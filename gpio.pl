#!/usr/bin/perl
use warnings;
use strict;
use autodie;
use Data::Dump qw(dump);

sub slurp {
	open(my $fh, '<', shift);
	local $/ = undef;
	<$fh>;
}

my $pins;

my $model = slurp('/proc/device-tree/model');

my @lines;
my $line_i = 0;

while(<DATA>) {
	chomp;
	push @lines, $_;
	push @{ $pins->{$1} }, $line_i while ( m/\t(P\w\w+)\s/g );
	$line_i++;
}

warn "# pins ",dump($pins);

open(my $fh, '<', '/sys/kernel/debug/pinctrl/pinctrl-handles');
while(<$fh>) {
	chomp;
	if ( m/group: (P\w\d+)\s.+function: (\S+)/ ) {
		my ($pin, $function) = ($1,$2); 
		if ( $pins->{$pin} ) {
			foreach my $line ( @{$pins->{$pin}} ) {
warn "XXX $pin $line";
				my $t = $lines[$line];
				$t =~ s/$pin/$pin [$function]/ || die "can't find $pin in [$t]";
				$lines[$line] = $t;
				warn "# $line: $lines[$line]\n";
			}
		} else {
			warn "IGNORED: pin $pin function $function\n";
		}
	}
};

my @max_len = ( 0,0,0,0 );
my @line_parts;
foreach my $line (@lines) {
	if ( $line =~ m/^#/ ) {
		push @line_parts, [ $line ];
		next;
	}
	my @v = split(/\s*\t+\s*/,$line,4);
	push @line_parts, [ @v ];
	foreach my $i ( 0 .. 3 ) {
		my $l = length($v[$i]);
		$max_len[$i] = $l if $l > $max_len[$i];
	}
}

warn "# max_len = ",dump( \@max_len );
warn "# line_parts = ",dump( \@line_parts );

#print "$_\n" foreach @lines;

my $fmt = "%$max_len[0]s %-$max_len[1]s %$max_len[2]s %-$max_len[3]s\n";

foreach my $line ( @line_parts ) {
	if ( $#$line == 0 ) {
		print $line->[0], "\n";
	} else {
		printf $fmt, @$line;
	}
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
30 	PD26 (LCDHSYNC)-VGA-HSYNC	 	29 	PD24 (LCDCLK)
28 	PD23 (LCDD23) 				27 	PD27 (LCDVSYNC)-VGA-VSYNC
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
13 	PG6 (CSI1-D2/UART3-TX) 			14 	PG7 (CSI1-D3/UART3-RX
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
