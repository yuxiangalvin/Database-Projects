#!/usr/bin/perl -w

use Getopt::Long;
use Time::ParseDate;
use Time::CTime;
use FileHandle;
use JSON;
use Data::Dumper;

use Date::Manip;

$close=1;

$notime=0;
$open=0;
$high=0;
$low=0;
$close=0;
$vol=0;
$plot=0;
$from = "5 years ago";
$to = "now";

&GetOptions( "notime"=>\$notime,
             "open" => \$open,
	     "high" => \$high,
	     "low" => \$low,
	     "close" => \$close,
	     "vol" => \$vol,
	     "from=s" => \$from,
	     "to=s" => \$to, "plot" => \$plot);


if (!($from eq "5 years ago") || !($to eq "now")) { 
   die "Sorry, this code currently does not support --from and --to\n" .
       "  Only the last 5 years of data can be fetched\n";
}

#
# Not currently used - for future extension that supports
# arbitrary ranges
#
$from = parsedate($from);
$from = ParseDateString("epoch $from");
$to = parsedate($to);
$to = ParseDateString("epoch $to");


$usage = "usage: quotehist.pl [--open] [--high] [--low] [--close] [--vol] [--from=time] [--to=time] [--plot] SYMBOL\n";

$#ARGV == 0 or die $usage;

$symbol = shift;

if ($plot) { 
  open(DATA,">_plot.in") or die "Cannot open plot file\n";
  $output = DATA;
} else {
  $output = STDOUT;
}

$rawdata = `wget -O -  https://api.iextrading.com/1.0/stock/$symbol/chart/5y 2>/dev/null`;

#print $rawdata;

$q = decode_json($rawdata);

#print Dumper($q);

#
# q is a ref to an array of refs to hashes
#
#
 

foreach $r (@{$q}) {
  my @out;

  $qdate = $r->{date};
  $qopen = $r->{open};
  $qhigh = $r->{high};
  $qlow  = $r->{low};
  $qclose = $r->{close};
  $qvolume = $r->{volume};
  
  push @out, parsedate($qdate) if !$notime;
  push @out, $qopen if $open;
  push @out, $qhigh if $high;
  push @out, $qlow if $low;
  push @out, $qclose if $close;
  push @out, $qvolume if $vol;

  print $output join("\t",@out),"\n";
}

if ($plot) {
  close(DATA);
  open(GNUPLOT, "|gnuplot") or die "Cannot open gnuplot for plotting\n";
  GNUPLOT->autoflush(1);
  print GNUPLOT "set title '$symbol'\nset xlabel 'time'\nset ylabel 'data'\n";
  print GNUPLOT "plot '_plot.in' with linespoints;\n";
  STDIN->autoflush(1);
  <STDIN>;
}


