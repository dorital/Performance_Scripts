#!/usr/bin/perl

use strict;
use warnings ;
use Excel::Writer::XLSX;
use Spreadsheet::WriteExcel;

my $DIR = $ARGV[0] ;
my $line = "" ;
my $FLine = 1 ;

if ($DIR) { chomp $DIR ; }
else { exit 2 ; }

if (! -d $DIR) {
	print "can not rotk on : $DIR !\n" ;
	exit 1 ;
}

print "Change dir to : $DIR\n" ;
chdir ($DIR) ;

my $LastTest ;
my $title = 0 ;

my @colw = (11, 10, 10, 26, 11, 8, 9, 8, 8, 12, 12) ;
my $workbook  = Excel::Writer::XLSX->new( 'results.xlsx' );

my $worksheet = $workbook->add_worksheet('Configuration');
open(FH,"<configuration.json") ;# or die "Cannot open file: $!\n";
my ($x,$y) = (0,0);
while (<FH>){
   chomp;
   my @list = split /,/,$_;
   foreach my $c (@list){
      $worksheet->write($x, $y++, $c);
   }
   $x++; $y=0;
}
close(FH);

$worksheet = $workbook->add_worksheet('System_Info');
open(FH,"<system_info.csv") ;# or die "Cannot open file: $!\n";
($x,$y) = (0,0);
while (<FH>){
   chomp;
   my @list = split /,/,$_;
   foreach my $c (@list){
      $worksheet->write($x, $y++, $c);
   }
   $x++; $y=0;
}
close(FH);

   $worksheet = $workbook->add_worksheet('Results');
   $worksheet->hide_gridlines(2);
my $format = $workbook->add_format() ;

my %TitleFormat ;
foreach my $col ('A'..'K') {
	$TitleFormat{$col} = $workbook->add_format(
		align => 'center', 
		bold => 1, 
		top => 2, 
		bottom => 2
	) ;
	$TitleFormat{$col}->set_left(1) ;
	$TitleFormat{$col}->set_right(1) ;
}
foreach my $col ('A', 'D'..'F', 'I') {
	$TitleFormat{$col}->set_left(2) ;
	$TitleFormat{$col}->set_right(2) ;
}
$TitleFormat{'K'}->set_right(2) ;

my $LFormat ;
my %LineFormat ;
foreach my $key ('prealloc','warmup','max','curv','reg') {
	foreach my $col ('A'..'K') { 
		$LineFormat{$key}{$col} = $workbook->add_format() ;
		if ($col ge 'E' && $col le 'H') {
			$LineFormat{$key}{$col}->set_num_format('_ * #,##0_ ;_ * -#,##0_ ;_ * "-"??_ ;_ @_ ' );
		}
		if ($col ge 'I' && $col le 'K') {
			$LineFormat{$key}{$col}->set_num_format('_ * #,##0.000_ ;_ * -#,##0.000_ ;_ * "-"??_ ;_ @_ ' );
		}
		$LineFormat{$key}{$col}->set_border(1) ;
		if ($key !~ /reg/) {
			$LineFormat{$key}{$col}->set_top(2) ;
			$LineFormat{$key}{$col}->set_bottom(2) ;
		}
		if ($key eq 'max') {
			$LineFormat{$key}{$col}->set_bg_color(22) ;
			$LineFormat{$key}{$col}->set_color(23) ;
		}
		if ($key eq 'curv') {
			$LineFormat{$key}{$col}->set_bg_color(23) ;
		}
	}

	if ($key eq 'reg') {
		$LineFormat{$key}{'E'}->set_bg_color(24) ;
		$LineFormat{$key}{'F'}->set_bg_color(42) ;
		$LineFormat{$key}{'I'}->set_bg_color(45) ;
	}

	$LineFormat{$key}{'E'}->set_bold() ;
	$LineFormat{$key}{'F'}->set_bold() ;
	$LineFormat{$key}{'I'}->set_bold() ;

	$LineFormat{$key}{'B'}->set_num_format('hh:mm:ss') ;
	$LineFormat{$key}{'C'}->set_num_format('hh:mm:ss') ;
	$LineFormat{$key}{'D'}->set_bold() ;

	foreach my $col ('A', 'D'..'F', 'I') {
		$LineFormat{$key}{$col}->set_left(2) ;
		$LineFormat{$key}{$col}->set_right(2) ;
	}

	$LineFormat{$key}{'K'}->set_right(2) ;

	$LineFormat{$key}{'G'}->set_align('center') ;
}

my $LChart ;

sub autofit_columns {

    my $worksheet = shift;
    my $col       = 0;

    for my $width (@colw) {

        $worksheet->set_column($col, $col, $width) ;
        $col++;
    }
	my $fmt_hdr = $workbook->add_format( border=>1, color=>'blue' , align => 'center');
	$worksheet->set_selection( 'A1:K1');
	$worksheet->freeze_panes(1, 4);
}

sub Print {
	my $index = 'A' ;
	foreach my $Title ( @_ ) {
		if ($FLine == 1) {
			$format = $TitleFormat{$index} ;
		} else {
			$format = $LineFormat{$LFormat}{$index} ; 
		}
			if ($index ge 'E' && ($FLine > 1) && $index ne 'G') {
				$worksheet->write_number( "${index}${FLine}","$Title", $format) ;
			} else {
				$worksheet->write( "${index}${FLine}","$Title", $format) ;
			}
		$index++ ;
	}
	$FLine++ ;
}

Print ('Date','Start Time','End Time','Test','IOPS','MB/Sec','BlockSize','% Read','Latency','Read Latency','Write Latency') ;

for my $file (`ls -rt stdout_test_*`) {
	chomp $file ;
	$LastTest = "" ;
	print "Cleanup $file.....\n" ;
	open my $IN, "<", $file || die "can not open file" ;
	while (1) {
		my $Date = "" ;
		while ( $line !~ /Starting RD=/ && (! eof($IN))) { $line = <$IN> ; }
		if (eof($IN)){
			close ($IN) ;
			last ;
		}

		$LFormat = 'reg'  ;
		if ($line =~ /Uncontrolled MAX/)   { $LFormat = 'max' } ;
		if ($line =~ /prealloc/)           { $LFormat = 'prealloc' } ;
		if ($line =~ /warmup/)             { $LFormat = 'warmup' } ;

		my $StartTime = (split ('\.', $line))[0] ;
		my $Test = (split (' ', $line))[2] ;
		$Test =~ s/RD=//g ;
		$Test =~ s/;//g ;
		#print "=== $Test : $LastTest ===\n" ;
		if ($line =~ /For loops:/) {
			my $rpc = (split (':', $line))[-1] ;
			$rpc =~ s/ /_/g ;
			$rpc =~ s/rdpct=/R/ ;
			$rpc =~ s/rhpct=/RH/ ;
			$rpc =~ s/whpct=/WH/ ;
			$rpc =~ s/seekpct=/Rdm/ ;
			$rpc =~ s/xfersize=// ;
			
			#$rpc = (split ('=', $rpc))[-1] ;
			$Test = "$Test-$rpc" ;
			if (length($Test) > 31) { $Test = substr ($Test, 0, 30) ; }
			#print "--- $Test ---\n" ;
		}
		if ($line =~ /Uncontrolled curve/) { 
			$LFormat = 'curv' ;
			my $s = $FLine + 1 ;
			my $e = $FLine + 14 ;
			#print "   Creating Chart : $Test\n" ;
			$LChart = $workbook->add_chart( type => 'line', name => "$Test" ) || die "can not create chart for $Test"; 
			$LChart->add_series(
			        categories => "=Results!E$s:F$e",
			        values     => "=Results!I$s:I$e",
			        smooth     => 1,
			);
			$LChart->set_legend( position => 'none' );
			$LChart->set_title( name => "$Test - Latency" );
			$LChart->set_y_axis( name => "Latency" );
			$LChart->set_x_axis( name => "Bendwidth & IOPS" );
			$LChart = $workbook->add_chart( type => 'line', name => "${Test}1" ) || die "can not create chart for $Test"; 
			$LChart->add_series(
			        categories => "=Results!I$s:I$e",
			        values     => "=Results!E$s:E$e",
			        smooth     => 1,
			);
			$LChart->set_legend( position => 'none' );
			$LChart->set_title( name => "$Test - IOPS" );
			$LChart->set_y_axis( name => "IOPS" );
			$LChart->set_x_axis( name => "Latency" );
			$LastTest = $Test ;
		} ;
		while ( $line !~ /avg/) { 
			$line = <$IN> ; 
			if (eof($IN)){
				close ($IN) ;
				last ;
			}
			if ($line =~ /interval/ && $Date eq "") {
				my @Date = (split (' ', $line)) ;
				$Date = "$Date[0] $Date[1] $Date[2]" ;
				$Date =~ s/,//g ;
			}
		}
		my @Data = (split(' ', $line)) ;
		my $EndTime = (split('\.', $Data[0]))[0] ;
		my $BS = "" ;
		if ($Data[4] >= 1024) {
			$Data[4] = $Data[4] / 1024 ;
			$BS = "K" ;
		}
		if ($Data[4] >= 1024) {
			$Data[4] = $Data[4] / 1024 ;
			$BS = "M" ;
		}
		$Data[4] = $Data[4] . " $BS" ;
		if ($Test =~ /\%\)/) {
			$Test = (split ('\(', $Test))[1] ;
			$Test =~ s/\)// ;
		}
		Print ("$Date","$StartTime","$EndTime","$Test",@Data[2..8]) ;
	}
}
autofit_columns($worksheet);


$workbook->close;
