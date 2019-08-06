#!/usr/bin/perl -w

use Getopt::Long;
use strict;
use CGI qw(:standard);
use DBI;
use Time::ParseDate;

BEGIN {
  $ENV{PORTF_DBMS}="oracle";
  $ENV{PORTF_DB}="cs339";
  $ENV{PORTF_DBUSER}="yhl4722";
  $ENV{PORTF_DBPASS}="zf39ejgQN";

  unless ($ENV{BEGIN_BLOCK}) {
    use Cwd;
    $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
    $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
    $ENV{ORACLE_SID}="CS339";
    $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',cwd().'/'.$0,@ARGV;
  }
};

#$#ARGV>=2 or die "usage: time_series_symbol_project.pl symbol steps-ahead model \n";

my $symbol=param('symbol');
my $days=param('days');
my $num_hist = param('num_hist');
#$model=join(" ",@ARGV);
my $model="AWAIT $num_hist AR 16";


system "./get_data.pl --notime --close $symbol > _data.in";
#my $out = `./get_data.pl --notime --close $symbol`;
#print $out;
system "./time_series_project _data.in $days $model > _prediction.in";


print header(-type => 'image/png', -expires => '-1h' );

open(GNUPLOT,"| gnuplot") or die "Cannot run gnuplot";
  
  print GNUPLOT "set term png\n";           # we want it to produce a PNG
  print GNUPLOT "set output\n";             # output the PNG to stdout
  print GNUPLOT "plot '_prediction.in' using 1:2 with linespoints, '_prediction.in' using 1:3 with linespoints\n"; # feed it data to plot

  #
  # Here gnuplot will print the image content
  #

close(GNUPLOT);