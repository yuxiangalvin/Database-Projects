#!/usr/bin/perl -w

use Data::Dumper;
use Finance::Quote;

$#ARGV>=0 or die "usage: quote.pl  SYMBOL+\n";


@info=("date","time","high","low","close","open","last","volume");


@symbols=@ARGV;

$con=Finance::Quote->new('IEX');

$con->timeout(60);

%quotes = $con->fetch("iex",@symbols);

foreach $symbol (@ARGV) {
    print $symbol,"\n=========\n";
    if (!defined($quotes{$symbol,"success"})) { 
	print "No Data\n";
    } else {
#        print Dumper(\%quotes);
	foreach $key (@info) {
	    if (defined($quotes{$symbol,$key})) {
		print $key,"\t",$quotes{$symbol,$key},"\n";
	    }
	}
    }
    print "\n";
}


