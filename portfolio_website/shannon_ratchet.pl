#!/usr/bin/perl -w 

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

$#ARGV==2 or die "usage: shannon_ratchet.pl symbol initialcash tradingcost\n";

($symbol, $initialcash,$tradecost) = @ARGV;


$lastcash=$initialcash;
$laststock=0;
$lasttotal=$lastcash;
$lasttotalaftertradecost=$lasttotal;

open(STOCK, "./get_data.pl --close $symbol |");


$cash=0;
$stock=0;
$total=0;
$totalaftertradecost=0;

$day=0;



while (<STOCK>) { 
  chomp;
  @data=split;
  $stockprice=$data[1];

  $currenttotal=$lastcash+$laststock*$stockprice;
  if ($currenttotal<=0) {
    exit;
  }
  
  $fractioncash=$lastcash/$currenttotal;
  $fractionstock=($laststock*$stockprice)/$currenttotal;
  $thistradecost=0;
  if ($fractioncash >= 0.5 ) {
    $redistcash=($fractioncash-0.5)*$currenttotal;
    if ($redistcash>0) {
      $cash=$lastcash-$redistcash;
      $stock=$laststock+$redistcash/$stockprice;
      $thistradecost=$tradecost;
    } else {
      $cash=$lastcash;
      $stock=$laststock;
    } 
  }  else {
    $redistcash=($fractionstock-0.5)*$currenttotal;
    if ($redistcash>0) {
      $cash=$lastcash+$redistcash;
      $stock=$laststock-$redistcash/$stockprice;
      $thistradecost=$tradecost;
    }
  }
  
  $total=$cash+$stock*$stockprice;
  $totalaftertradecost=($lasttotalaftertradecost-$lasttotal) - $thistradecost + $total; 
  $lastcash=$cash;
  $laststock=$stock;
  $lasttotal=$total;
  $lasttotalaftertradecost=$totalaftertradecost;

  $day++;
  

#  print STDERR "$day\t$stockprice\t$cash\t".($stock*$stockprice)."\t$stock\t$total\t$totalaftertradecost\n";
}

close(STOCK);

$roi = 100.0*($lasttotal-$initialcash)/$initialcash;
$roi_annual = $roi/($day/365.0);

$roi_at = 100.0*($lasttotalaftertradecost-$initialcash)/$initialcash;
$roi_at_annual = $roi_at/($day/365.0);


#print "$symbol\t$day\t$roi\t$roi_annual\n";

		
print "Invested:                        \t$initialcash\n";
print "Days:                            \t$day\n";
print "Total:                           \t$lasttotal (ROI=$roi % ROI-annual = $roi_annual %)\n";
print "Total-after \$$tradecost/day trade costs: \t$lasttotalaftertradecost (ROI=$roi_at % ROI-annual = $roi_at_annual %)\n";
	
		

