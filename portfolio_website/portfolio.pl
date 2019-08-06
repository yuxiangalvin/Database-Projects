#!/usr/bin/perl -w

#
#
# rwb.pl (Red, White, and Blue)
#
#
# Example code for EECS 339, Northwestern University
#
# Peter Dinda
#

# The overall theory of operation of this script is as follows
#
# 1. The inputs are form parameters, if any, and a session cookie, if any.
# 2. The session cookie contains the login credentials (User/Password).
# 3. The parameters depend on the form, but all forms have the following three
#    special parameters:
#
#         act      =  form  <the form in question> (form=base if it doesn't exist)
#         run      =  0 Or 1 <whether to run the form or not> (=0 if it doesn't exist)
#         debug    =  0 Or 1 <whether to provide debugging output or not>
#
# 4. The script then generates relevant html based on act, run, and other
#    parameters that are form-dependent
# 5. The script also sends back a new session cookie (allowing for logout functionality)
# 6. The script also sends back a debug cookie (allowing debug behavior to propagate
#    to child fetches)
#

#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug     = 0;   # default - will be overriden by a form parameter or cookie
my @sqlinput  = ();
my @sqloutput = ();

#
# The combination of -w and use strict enforces various
# rules that make the script more resilient and easier to run
# as a CGI script.
#
use strict;

# The CGI web generation stuff
# This helps make it easy to generate active HTML content
# from Perl
#
# We'll use the "standard" procedural interface to CGI
# instead of the OO default interface
use CGI qw(:standard);

# The interface to the database.  The interface is essentially
# the same no matter what the backend database is.
#
# DBI is the standard database interface for Perl. Other
# examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
#
#
# This will also load DBD::Oracle which is the driver for
# Oracle.
use DBI;

#
#
# A module that makes it easy to parse relatively freeform
# date strings into the unix epoch time (seconds since 1970)
#
use Time::ParseDate;

#
# You need to override these for access to your database
#
my $dbuser   = "yhl4722";
my $dbpasswd = "zf39ejgQN";

#
# You need to supply a google maps API key
#
# More info here:
#   https://developers.google.com/maps/documentation/javascript/get-api-key
#
 my $googlemapskey = "AIzaSyC10n9TO6fff6fsVR_aCyNiGyeMXLjZbX4";
# my $googlemapskey = "AIzaSyB2TETgkE5CpE47RP0D-17m5kFUdg5z3uk";

#
# The session cookie will contain the user's name and password so that
# he doesn't have to type it again and again.
#
# "RWBSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
my $cookiename = "PTFLSession";
#
# And another cookie to preserve the debug state
#
my $debugcookiename = "PTFLDebug";

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent      = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);

#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent      = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie             = 0;
my $user                     = undef;
my $password                 = undef;
my $logincomplain            = 0;

# bug-potential: should initiate as an empty array

#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
my $action;
my $run;
my $portfolio_id;

if ( defined( param("act") ) ) {
    $action = param("act");
    if ( defined( param("run") ) ) {
        $run = param("run") == 1;
    }
    else {
        $run = 0;
    }
}
else {
    $action = "base";
    $run    = 1;
}
######################
if ( defined( param("portfolio_id") ) ) {
    $portfolio_id = param("portfolio_id");
}
###################

my $dstr;

if ( defined( param("debug") ) ) {

    # parameter has priority over cookie
    if ( param("debug") == 0 ) {
        $debug = 0;
    }
    else {
        $debug = 1;
    }
}
else {
    if ( defined($inputdebugcookiecontent) ) {
        $debug = $inputdebugcookiecontent;
    }
    else {
        # debug default from script
    }
}

$outputdebugcookiecontent = $debug;

#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if ( defined($inputcookiecontent) ) {

    # Has cookie, let's decode it
    ( $user, $password ) = split( /\//, $inputcookiecontent );
    $outputcookiecontent = $inputcookiecontent;
}
else {
    # No cookie, treat as anonymous user
    ( $user, $password ) = ( "anon\@anonymous.com", "anonanon" );
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ( $action eq "login" ) {
    if ($run) {
        #
        # Login attempt
        #
        # Ignore any input cookie.  Just validate user and
        # generate the right output cookie, if any.
        #
        ( $user, $password ) = ( param('user'), param('password') );
        if ( ValidUser( $user, $password ) ) {

            # if the user's info is OK, then give him a cookie
            # that contains his username and password
            # the cookie will expire in one hour, forcing him to log in again
            # after one hour of inactivity.
            # Also, land him in the base query screen
            $outputcookiecontent = join( "/", $user, $password );
            $action              = "base";
            $run                 = 1;
        }
        else {
            # uh oh.  Bogus login attempt.  Make him try again.
            # don't give him a cookie
            $logincomplain = 1;
            $action        = "login";
            $run           = 0;
        }
    }
    else {
        #
        # Just a login screen request, but we should toss out any cookie
        # we were given
        #
        undef $inputcookiecontent;
        ( $user, $password ) = ( "anon\@anonymous.com", "anonanon" );
    }
}

sub ValidUser {
    my ( $user, $password ) = @_;
    my @col;
    eval {
        @col =
          ExecSQL( $dbuser, $dbpasswd,
            "select count(*) from portfolio_users where email=? and password=?",
            "COL", $user, $password );
    };
    if ($@) {
        return 0;
    }
    else {
        return $col[0] > 0;
    }
}

#
# If we are being asked to log out, then if
# we have a cookie, we should delete it.
#
if ( $action eq "logout" ) {
    $deletecookie = 1;
    $action       = "base";
    $user         = "anon\@anonymous.com";
    $password     = "anonanon";
    $run          = 1;
}

my @outputcookies;

#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if ( defined($outputcookiecontent) ) {
    my $cookie = cookie(
        -name    => $cookiename,
        -value   => $outputcookiecontent,
        -expires => ( $deletecookie ? '-1h' : '+1h' )
    );
    push @outputcookies, $cookie;
}

#
# We also send back a debug cookie
#
#
if ( defined($outputdebugcookiecontent) ) {
    my $cookie = cookie(
        -name  => $debugcookiename,
        -value => $outputdebugcookiecontent
    );
    push @outputcookies, $cookie;
}

#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#
print header( -expires => 'now', -cookie => \@outputcookies );

#
# Now we finally begin generating back HTML
#
#
#print start_html('Red, White, and Blue');
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Portfolio Manager</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

#
# Force device width, for mobile phones, etc
#
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
#
print "<style type=\"text/css\">\n\@import \"portfolio.css\";\n</style>\n";

print "<p><b>YOU NEED TO SET DBUSER</b></p>"   if ( $dbuser eq "CHANGEME" );
print "<p><b>YOU NEED TO SET DBPASSWD</b></p>" if ( $dbpasswd eq "CHANGEME" );


print "<center>" if !$debug;
print "<h1 class='greeting'><b>HELLO!</b></h1>";
print ul({-class=>'nav-bar'},
            li(a({-href =>'Part1.pdf', -class=>'nav' }, "User Flow")),
            li(a({href=>'Part2.png', -class=>'nav'}, "ER Diagram")),
            li(a({href=>'Part3.PNG', -class=>'nav'}, "Relational Schema")),
            li(a({href=>'part4.txt', -class=>'nav'}, "SQL DDL")),
            li(a({href=>'part5.txt', -class=>'nav'}, "SQL DML")));

if ( $action eq "login" ) {
    if ($logincomplain) {
        print "Login failed.  Try again.<p>";
    }
    if ( $logincomplain or !$run ) {
        print start_form( -name => 'Login' ),
        h2('Login to HCL Portfolio Manager'),
        "Email:", textfield( -name => 'user' ), p,
        "Password:", password_field( -name => 'password' ), p,
        hidden( -name => 'act', default => ['login'] ),
        hidden( -name => 'run', default => ['1'] ),
        submit,
        end_form;
    }
}

if ( $action eq "create-account" ) {
    ## not finished: check if the clicked link is used

    # if ( registeredInviteKey($id) == 1 ) {
    #     print h2('Your link has been used.');
    # }
    # ## check if the uuid exists, if not, print warning message
    # # query invited_users table

    # elsif ( $uuid_exist[0][0] == 0 ) {
    #     print h2('Your link is invalid.');
    # }

    if ( !$run ) {
        ## check if the uuid exists, if not, print warning message
        # query invited_users table

        print start_form( -name => 'CreateAccount' ),
          h2('Create your account here'),
          "Name: ",     textfield( -name => 'name' ),     p,
          "Email: ",    textfield( -name => 'email' ),    p,
          "Password: ", password_field( -name => 'password' ), p,
          hidden( -name => 'run',       -default => ['1'] ),
          hidden( -name => 'act',       -default => ['create-account'] ),
          submit,
          end_form,
          hr;
    }
    else {
        my $name  = param('name');
        my $email = param('email');
        my $pw    = param('password');
        ## query for the referer from the invited_users table
        # bug-potential: can we refer to $id in this scope?
        my $error;
        $error = UserAdd( $name, $pw, $email);
        if ($error) {
            print "Can't create account because: $error";
        }
        else {
            ## grant permissions to users
            # query permissions from the invited_users table
            # my @granted_permissions;
            # eval {
            #     @granted_permissions =
            #       ExecSQL( $dbuser, $dbpasswd,
            #         "select action from invited_permissions where uuid=?",
            #         'COL', $id );
            # };

            # store granted permissions in the rwb_permissions table
            # foreach (@granted_permissions) {
            #     eval {
            #         ExecSQL( $dbuser, $dbpasswd,
            #             "insert into rwb_permissions values(\'$name\', \'$_\')"
            #         );
            #     };
            # }

            # mark the registered flag as 1 in the invited_users table
            # eval {
            #     ExecSQL( $dbuser, $dbpasswd,
            #         "update invited_users set registered=1 where uuid=?",
            #         undef, $id );
            # };

            # print success message
            print "You have successfully created your account.";
            print
            "Created user $name with email $email";
        }
    }
    print "<p><a href=\"portfolio.pl?act=base&run=0\">Return</a></p>";
}

###############
sub UserAdd {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "insert into portfolio_users (name,password,email) values (?,?,?)",
            undef,
            @_
        );
    };
    return $@;
}


#################
if ( $action eq "base" ) {
    CreateHistory("SPY");
    print "<p><a class='fake-button' href=\"portfolio.pl?act=login\">LOGIN<a></p>";
    print "<p><a class='fake-button' href=\"portfolio.pl?act=create-account\">SIGN UP<a></p>";

    my @user_portfolios = undef;
    @user_portfolios = FetchPortfolio($user);

    print "<p>Your Portfolios:</p>";
    foreach (@user_portfolios) {
        my $id = $_->[0];
        print "<p><a class='fake-button' href=\"portfolio.pl?act=portfolio&portfolio_id=$id\">$id<a></p>";
    }
    
    if(!($user eq "anon\@anonymous.com")){
        print "<p><a class='fake-button' href=\"portfolio.pl?act=create-portfolio\">Create New Portfolio<a></p>";
    }
    #
    # And a div to populate with info about nearby stuff
    #
    #
    if ($debug) {
        # visible if we are debugging
        print "<div id=\"data\" style=\:width:100\%; height:10\%\"></div>";
    }
    else {
        # invisible otherwise
        print "<div id=\"data\" style=\"display: none;\"></div>";
    }

# height=1024 width=1024 id=\"info\" name=\"info\" onload=\"UpdateMap()\"></iframe>";
}

sub FetchPortfolio {
    my @user_portfolios = undef;
    eval {
        @user_portfolios = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select id from portfolio_portfolio where user_email = ?",
            undef,
            @_
        );
    };
    return @user_portfolios;
}

if ($action eq "create-portfolio") {
    if ( !$run ) {
        print start_form( -name => 'CreatePortfolio' ),
          h2('Create your portfolio here'),
          "Cash: ", textfield( -name => 'cash' ), p,
          hidden( -name => 'run',       -default => ['1'] ),
          hidden( -name => 'act',       -default => ['create-portfolio'] ),
          submit,
          end_form,
          hr;
    }
    else{
        my $cash;
        $cash = param('cash');
        ## query for the referer from the invited_users table
        # bug-potential: can we refer to $id in this scope?
        my $error;
        $error = PortfolioAdd($user, $cash);
        if ($error) {
            print "$user";
            print "Can't create account because: $error";
        }
        else {
            # print success message
            print "You have successfully created your account.";
            print
            "Created a portfolio with email $user and cash $cash.";
        }
    }
    print "<p><a href=\"portfolio.pl?act=base&run=1\">Return to Dashboard</a></p>";
}

###############
sub PortfolioAdd {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "insert into portfolio_portfolio (id, user_email, cash) values (seq_portfolio.nextval, ?,?)",
            undef,
            @_
        );
    };
    return $@;
}


#######
if ( $action eq "portfolio" ){
    print "<p>This is your portfolio - $portfolio_id </p>";
    my $cash = CheckCash();
    print "<p>Account Cash: $cash dollars</p>";
    my @stock_table = FetchStocks($portfolio_id);
    # use Data::Dumper;
    # print Dumper(\@stock_table);
    my $portfolio_value = 0;
    print "<p>Your Stocks:</p>";
    my $stock_number = scalar(@stock_table);
    for (my $i=0; $i < $stock_number; $i++) {
        my $stock = $stock_table[$i][0];
        my $share = CheckHolding($stock);
        my %quote_hashtable = SymbolToHash($stock);
        my $strike_price = $quote_hashtable{'close'};
        my $value = $strike_price * $share;
        my $coef_var = GetCoefVar($stock);
        my $beta = GetBeta($stock);
        $portfolio_value = $portfolio_value + $value;
        print "<p>Stock Symbol: <a class='fake-button' href=\"portfolio.pl?act=stock&portfolio_id=$portfolio_id&symbol=$stock_table[$i][0]\"> $stock_table[$i][0] </a> Number of Shares:$share; 
                Total Market Value: $value;
                Coeffecient of Variation: $coef_var;
                Beta: $beta</p>";
    }

    my $preTradeDayTS = ExecSQL($dbuser, $dbpasswd,"select max(timestamp) from all_stocks");

    # $portfolio_value = ExecSQL($dbuser, $dbpasswd,"select sum(shares*close) from stock_holdings where timestamp = ?", undef, $preTradeDayTS);
    


    print "<p>Portfolio Total Present Market Value: $portfolio_value</p>";

    my $volatility = PortfolioVolatility($portfolio_id, $portfolio_id);
    print "<p>Portfolio Volatility according to holding stocks' history: $volatility</p>";
    
    print "<p>---------------------------------------------</p>";
    print "<p>Functions:</p>";
    print "<p><a class='fake-button' href=\"portfolio.pl?act=buy-stock&portfolio_id=$portfolio_id\">Buy Stock</a></p>";
    print "<p><a class='fake-button' href=\"portfolio.pl?act=sell-stock&portfolio_id=$portfolio_id\">Sell Stock</a></p>";

    print "<p><a class='fake-button' href=\"portfolio.pl?act=deposit&portfolio_id=$portfolio_id\">Deposit Cash</a></p>";
    print "<p><a class='fake-button' href=\"portfolio.pl?act=withdraw&portfolio_id=$portfolio_id\">Withdraw Cash from Account</a></p>";
    #print "<p><a class='fake-button' href=portfolio.pl?act=transfer&portfolio_id=$portfolio_id>Transfer Cash</a></p>";

    print "<p><a class='fake-button' href=\"portfolio.pl?act=trading_strategy&portfolio_id=$portfolio_id\">Automated Strategy</a></p>";
    print "<p><a class='fake-button' href=\"portfolio.pl?act=prediction&portfolio_id=$portfolio_id\">Predict Stock Price</a></p>";

    print "<p><a class='fake-button' href=\"portfolio.pl?act=correlation&portfolio_id=$portfolio_id\">Get Correlation Matrix</a></p>";

    print "<p><a href=\"portfolio.pl?act=base&run=1\">Return To Account Dashboard</a></p>";
}

sub PortfolioVolatility {
    my @volatility = undef;
    eval {
        @volatility =
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "with PI as (select symbol, shares, buy_price, close, timestamp from stock_holdings natural join stocks where portfolio_id =?), PI2 as (select symbol, shares, buy_price, close, timestamp from stock_holdings natural join stocks where portfolio_id=?), CalcPart2 as (select PI.symbol as symbol1, PI.shares as shares1, PI.buy_price as price1, PI.close as close1, PI2.symbol as symbol2, PI2.shares as shares2, PI2.buy_price as price2, PI2.close as close2 from PI cross join PI2 where PI.timestamp = PI2.timestamp), S1 AS (select sum(avg(shares1)*avg(price1)*avg(shares2)*avg(price2)*covar_pop(close1, close2)/sum(price1*shares1)/sum(price2*shares2)) as value from CalcPart2 where shares1 <> 0 and shares2 <> 0 group by symbol1, symbol2) select value from S1",
            undef,
            @_
        ); 
    };
    my $portfolio_volatility = @volatility ->[0] ->[0];
    return $portfolio_volatility;
}

sub FetchStocks {
    my @stock_table = undef;
    eval {
        @stock_table =
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select symbol, shares from stock_holdings where portfolio_id = ?",
            undef,
            @_
        ); 
    };
    return @stock_table;
}

if ($action eq "deposit" ) {
    if(!$run) {
        print "<h1>Deposit Your Money!</h1>";
        print start_form(-name => "deposit"),
            'Amount: ', textfield(-name => 'amount'), p, 
            hidden( -name => 'run',       -default => ['1'] ),
            hidden( -name => 'act',       -default => ['deposit'] ),
            hidden( -name => 'portfolio_id',       -default => [$portfolio_id] ),
            submit,
            end_form,
            hr;
    }
    else {
        my $amount  = param('amount');
        ## query for the referer from the invited_users table
        # bug-potential: can we refer to $id in this scope?
        my $error;
        $error = DepositCash($amount);
        if ($error) {
            print "Can't deposit cash because: $error";
        }
        else {
            print "You have successfully deposited your cash.";
            print
            "Deposit $amount dollars successfully into your portfolio $portfolio_id";
        }
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}

sub DepositCash {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "UPDATE portfolio_portfolio set cash = cash + ? where id = $portfolio_id",
            undef,
            @_
        );
    };
    return $@;
}

if ($action eq "withdraw" ) {
    if(!$run) {
        print "<h1>Withdraw Your Money!</h1>";
        print start_form(-name => "withdraw"),
            'Amount: ', textfield(-name => 'amount'), p, 
            hidden( -name => 'run',       -default => ['1'] ),
            hidden( -name => 'act',       -default => ['withdraw'] ),
            hidden( -name => 'portfolio_id',       -default => [$portfolio_id] ),
            submit,
            end_form,
            hr;
    }
    else {
        my $amount  = param('amount');
        my $portfolio_id = param('portfolio_id');
        ## query for the referer from the invited_users table
        # bug-potential: can we refer to $id in this scope?
        my $current_cash = CheckCash();
        if ($current_cash < $amount){
            print "Sorry, you only have $current_cash dollars in your portfolio $portfolio_id";
        }
        else{
             my $error;
            $error = WithdrawCash($amount);
            if ($error) {
                print "<p>Can't withdraw cash because: $error.</p>";
            }
            else {
                print "<p>You have successfully withdrawed money.</p>";
                print
                "<p>Withdraw $amount dollars successfully from your portfolio $portfolio_id.</p>";
            }
        }
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}

sub WithdrawCash {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "UPDATE portfolio_portfolio set cash = cash - ? where id = $portfolio_id",
            undef,
            @_
        );
    };
    return $@;
}

# if ($action eq "transfer" ) {
#     if(!$run) {
#         print "<h1>Withdraw Your Money!</h1>";
#         print start_form(-name => "withdraw"),
#             'Amount: ', textfield(-name => 'amount'), p, 
#             'Source Portfolio ID: ', textfield(-name => 'source_portfolio_id'), p,          
#             hidden( -name => 'run',       -default => ['1'] ),
#             hidden( -name => 'act',       -default => ['transfer'] ),
#             hidden( -name => 'portfolio_id',       -default => [$portfolio_id] ),
#             submit,
#             end_form,
#             hr;
#     }
#     else {
#         my $amount  = param('amount');
#         my $source_portfolio_id = param('source_portfolio_id');
#         ## query for the referer from the invited_users table
#         # bug-potential: can we refer to $id in this scope?
#         my $current_cash = CheckCash();
#         if ($current_cash < $amount){
#             print "Sorry, you only have $current_cash dollars in your portfolio $portifolio_id"
#         }
#         else{
#              my $error;
#             $error = WithdrawCash($amount);
#             if ($error) {
#                 print "Can't withdraw cash because: $error";
#             }
#             else {
#                 print "You have successfully withdrawed money.";
#                 print
#                 "Withdraw $amount dollars successfully from your portfolio $portfolio_id";
#             }
#         }
#     }
# }

# sub WithdrawCash {
#     eval {
#         ExecSQL(
#             $dbuser,
#             $dbpasswd,
#             "UPDATE portfolio_portfolio set cash = cash - ? where portfolio_id = $portfolio_id)",
#             undef,
#             @_
#         );
#     };
#     return $@;
# }

if ($action eq "buy-stock" ) {
    if(!$run) {
        print "<h1>Buy New Stocks!</h1>";
        print start_form(-name => "buy-stocks"),
            'Symbol of stock: ', textfield(-name => 'symbol'),p,
            'Amount: ', textfield(-name => 'amount'), p, 
            hidden( -name => 'run',       -default => ['1'] ),
            hidden( -name => 'act',       -default => ['buy-stock'] ),
            hidden( -name => 'portfolio_id',       -default => [$portfolio_id] ),
            submit,
            end_form,
            hr;
    }
    else {
        # call quote.pl to get most recent price
        my $symbol = param("symbol");
        # multiple by amount to find price.
        # check against cash
        # if enough cash
            # decrease cash
            # add stocks to portfolio with SQL
        # not enough cash, throw error.
        my %quote_hashtable = SymbolToHash($symbol);
        my $strike_price = $quote_hashtable{'close'};
        if ($strike_price == "(null)"){
            print "<p>Stock $symbol does not exist.</p>";
            print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
            die;
        }
        my $amount = param("amount");
        my $current_cash = CheckCash();
        print "<p>Your original cash is $current_cash.</p>";
        print "<p>The current share price is $strike_price.</p>";
        my $total_cost = $amount * $strike_price;
        if ($current_cash < $total_cost){
            print "<p>You don't have enough cash in this account.</p>";
            print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
            die;
        }
        else{
            print("<p>You have enough money.</p>");
            my $stock_exist = CheckHistoryExist($symbol);
            my $own_stock = CheckOwnStock($symbol);
            # use Data::Dumper;
            # print "<p>----before create hist---</p>";
            # print Dumper(\$stock_exist);
            if ($stock_exist == '(null)'){
                print "<p>----stock $symbol does not have data in history table---</p>";
                print "<p>----We are loading $symbol's data into database. Please patiently wait for about 40 seconds.---</p>";
                my $result = CreateHistory($symbol);
                $stock_exist = CheckHistoryExist($symbol);
                if ($stock_exist != '(null)'){
                    print "<p>----stock $symbol is successfully added into stock history table---</p>";
                }
                else{
                    print "<p>Fail to add $symbol into stock history table</p>";
                    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
                    die;
                }
            }
            # use Data::Dumper;
            # print "<p>----after create hist---</p>";
            # print Dumper(\$stock_exist);
            my $average_cost = $strike_price;
            if ($own_stock == '(null)'){
                print "<p> This is your first time to buy $symbol. </p>";
                # Create the stock in user's holding table, also check whether this stock is in stocks table, if not, insert its historical result.
                my $error = CreateStock($portfolio_id, $symbol, $strike_price);
                if ($error) {
                print "$user";
                print "Can't buy the stock because: $error";
                die;    
                }
            }else{
                my $former_value = CheckFormerValue($symbol);
                my $former_holding = CheckHolding($symbol);
                $average_cost = ($former_value + $total_cost)/($former_holding + $amount);
            }
            # If the code reaches here, all the possible conditions are checked to ensure that cash change ad stock change will both be successful.
            my $error = WithdrawCash($total_cost);
            if ($error) {
                print "$user";
                print "<p> Can't deduct money because: $error </p>";
                die;
            }
            my $error = BuyStock($amount, $average_cost, $portfolio_id, $symbol);
            if ($error) {
                print "$user";
                print "<p> Can't buy the stock because: $error </p>";
                die;
            }
            else {
            # print success message
            print "<p> You have successfully purchase $amount share(s) of $symbol with $total_cost dollars. </p>";
            my $remained_cash = CheckCash();
            print "<p> Your remaining cash is $remained_cash dollars. </p>";
            }
        }
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}
sub CheckFormerValue {
    my @value = undef;
    eval {
        @value = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select shares * buy_price from stock_holdings where ID = $portfolio_id and symbol = ?",
            undef,
            @_
        );
    };
    my $former_value = @value->[0]->[0];
    return $former_value;
}

sub SymbolToHash {
    my $response =`source ./setup_ora.sh; ./quote.pl @_`;
    my @quotes = split('\n', $response);
    my %quote_detail;
    foreach (@quotes) {
        my @detail = split(' ');
        $quote_detail{@detail->[0]} =  @detail->[1];
    }
    return %quote_detail;
}

sub SymbolToHashHistory {
    my $response =`source ./setup_ora.sh; ./quotehist.pl --open --high --low --close --vol @_`;
    # print "<p>------</p>";
    # print Dumper(\$response);
    my @quotes = split('\n', $response);
    # print "<p>------</p>";
    # print Dumper(\@quotes);
    my %quote_detail;
    # print "<p>------</p>";
    # print Dumper(\%quote_detail);
    foreach (@quotes) {
        my @detail = split(' ');
        my %data_hash;
        $data_hash{'open'} = @detail ->[1];
        $data_hash{'high'} = @detail ->[2];
        $data_hash{'low'} = @detail ->[3];
        $data_hash{'close'} = @detail ->[4];
        $data_hash{'volume'} = @detail ->[5];
        $data_hash{'from_time'} = @detail ->[6];
        $data_hash{'to_time'} = @detail ->[7];
        $data_hash{'plot'} = @detail ->[8];
        # print "<p>------</p>";
        # print Dumper(\%data_hash);
        $quote_detail{@detail->[0]} = \%data_hash;
    }
    return %quote_detail;
}

sub SymbolToArrayHistory {
    my $response =`source ./setup_ora.sh; ./quotehist.pl --open --high --low --close --vol @_`;
    # print "<p>------</p>";
    # print Dumper(\$response);
    my @quotes = split('\n', $response);
    # print "<p>------</p>";
    # print Dumper(\@quotes);
    my @quote_detail_array;
    # print "<p>------</p>";
    # print Dumper(\%quote_detail);
    foreach (@quotes) {
        my @data_array = split(' ');
        push @data_array, @_;
        push @quote_detail_array, \@data_array;
    }
    return @quote_detail_array;
}

sub CheckOwnStock {
    my @check_table = undef;
    eval {
        @check_table = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select symbol from stock_holdings where portfolio_ID = $portfolio_id and symbol = ?",
            undef,
            @_
        );
    };
    # use Data::Dumper;
    # print Dumper(\@check_table);
    return @check_table;
}

sub BuyStock {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            #"BEGIN TRANSACTION; UPDATE stock_holdings set shares = shares + ? where portfolio_id = $portfolio_id and symbol = ?; UPDATE portfolio_portfolio set cash = cash - ? WHERE ID = $portfolio_id; COMMIT;",
            "UPDATE stock_holdings set shares = shares + ?, buy_price = ? where portfolio_id = ? and symbol = ?",
            undef,
            @_
        );
    };
    return $@;
}

sub CreateStock {
    #Check and Create the stock in our stocks table if needed
    #Add this stock to the portfolio's holdings with 0 share
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "insert into stock_holdings (portfolio_ID,symbol,shares, buy_price) values (?,?,0,?)",
            undef,
            @_
        );
    };
    return $@;
}

sub CheckHistoryExist {
    my @exist_table = undef;
    eval {
        @exist_table = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select symbol from stocks where symbol = ?",
            undef,
            @_
        );
    };
    return @exist_table;
}

sub CreateHistory {
    #Following code create the stock in the history data
    
    # my %quotes_hash = SymbolToHashHistory(@_);
    # use Data::Dumper;
    # print Dumper(\%quotes_hash);
    
    my @quote_hist_array = SymbolToArrayHistory(@_);

    foreach(@quote_hist_array){
        # use Data::Dumper;
        # print Dumper(\$_);
        my @detail = $_;
        my $timestamp = $detail[0][0];
        my $open = @detail -> [0] -> [1];
        my $high = @detail -> [0] -> [2];
        my $low = @detail -> [0] -> [3];
        my $close = @detail -> [0] -> [4];
        my $volume = @detail -> [0] -> [5];
        my $symbol_temp = @detail -> [0] -> [6];
             
        eval {
          ExecSQL(
            $dbuser,
            $dbpasswd,
            "insert into stocks (timestamp,open,high,low,close,volume,symbol) values (?,?,?,?,?,?,?)",
            undef,
            $timestamp, $open, $high, $low,$close, $volume, $symbol_temp
            );
        };
        if ($@) {
            return $@
        }
    }
    return 1;
}

sub CheckCash {
    my @cash_table = undef;
    eval {
        @cash_table = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select cash from portfolio_portfolio where ID = $portfolio_id",
            undef,
            @_
        );
    };
    my $cash = @cash_table->[0]->[0];
    return $cash;
}

if ( $action eq "sell-stock" ) {
    if(!$run) {
        print "<h1>Sell New Stocks!</h1>";
        print start_form(-name => "sell-stocks"),
            'Symbol of stock: ', textfield(-name => 'symbol'),p,
            'Amount: ', textfield(-name => 'amount'), p, 
            hidden( -name => 'run',       -default => ['1'] ),
            hidden( -name => 'act',       -default => ['sell-stock'] ),
            hidden( -name => 'portfolio_id',       -default => [$portfolio_id] ),
            submit,
            end_form,
            hr;
    }
    else {
        # call quote.pl to get most recent price
        my $symbol = param("symbol");
        my $holding_shares = CheckHolding($symbol);
        my $amount = param("amount");
        if ($holding_shares == "(null)"){
            print "<p>You don't have $symbol in this portfolio.</p>";
            print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
            die;
        }
        elsif ($holding_shares < $amount){
            print "<p>You don't have enough shares. You only have $holding_shares $symbol in this portfolio.</p>";
            print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
            die;
        }
        else{
            my %quote_hashtable = SymbolToHash($symbol);
            my $strike_price = $quote_hashtable{'close'};
            my $total_revenue = $amount * $strike_price;

            # If the code reaches here, all the possible conditions are checked to ensure that cash change ad stock change will both be successful.
            my $error = SellStock($amount, $symbol);
            if ($error) {
                print "$user";
                print "<p> Can't sell the stock $symbol because: $error </p>";
            }
            else {
                my $error = DepositCash($total_revenue);
                if (!$error){
                    # print success message
                    print "<p> You have successfully sell $amount share(s) of $symbol and get $total_revenue dollars.</p>";
                    my $remained_cash = CheckCash();
                    my $remained_share = CheckHolding($symbol);
                    print "<p>Your remaining share(s) of is $remained_share. </p>";
                    print "<p>Your remaining cash is $remained_cash dollars.</p>";
                }
            }
        }
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}

sub CheckHolding {
    my @holding_table = undef;
    eval {
        @holding_table = 
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "select shares from stock_holdings where portfolio_ID = $portfolio_id and symbol = ?",
            undef,
            @_
        );
    };
    my $holding = @holding_table->[0]->[0];
    return $holding;
}

sub SellStock {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
            "UPDATE stock_holdings set shares = shares - ? where portfolio_id = $portfolio_id and symbol = ?",
            undef,
            @_
        );
    };
    return $@;
}

if ($action eq 'trading_strategy'){
    if(!$run) {
        my @trading_strategy = ("Shannon Ratchet");
        print start_form( -name => 'Automated Trading Strategy' ),
        "Stock Choice ", textfield( -name => 'symbol' ), p,
        "Cash ", textfield( -name => 'cash' ), p,
        "Trade Cost ", textfield( -name => 'trade_cost' ), p,
        hidden( -name => 'run', -default => ['1'] ),
        hidden( -name => 'act', -default => ['trading_strategy'] ),
        hidden( -name => 'portfolio_id', -default => [$portfolio_id] ),
        h5(
        'Please select trading strategy:'
        ),
        checkbox_group(
        -name   => 'trading_strategy',
        -values => \@trading_strategy
        ),p,
        submit, 
        end_form, 
        hr;
    }
    else {
        # call quote.pl to get most recent price
        #my $current_cash = CheckCash();
        my $trade_cost = param('trade_cost');
        my $cash = param('cash');
        my @strategy = param('trading_strategy');
        my $symbol = param('symbol');
        print "<p>Trading Strategy for $symbol: </p>";
        my $own_stock = CheckOwnStock($symbol);
        foreach (@strategy){
            print "$_:\n";
            use Data::Dumper;
            if ($_ eq "Shannon Ratchet"){
                my $response = qx/perl shannon_ratchet.pl $symbol $cash $trade_cost 2>&1/;
                print "<p>----------</p>";
                print "<p>$response</p>";
            }
        }
        # multiple by amount to find price.
        # check against cash
        # if enough cash
            # decrease cash
            # add stocks to portfolio with SQL
        # not enough cash, throw error.
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}

if ($action eq 'prediction'){
    if(!$run) {
        print start_form( -name => 'Predict Stock Price' ),
        "Stock Choice: ", textfield( -name => 'symbol' ), p,
        "Number of Days: ", textfield( -name => 'days' ), p,
        "Number of Previous Prices ", textfield( -name => 'num_hist' ), p,
        hidden( -name => 'run', -default => ['1'] ),
        hidden( -name => 'act', -default => ['prediction'] ),
        hidden( -name => 'portfolio_id', -default => [$portfolio_id] ),
        submit, 
        end_form, 
        hr;
    }
    else {
        # call quote.pl to get most recent price
        my $symbol = param('symbol');
        my $days = param('days');
        my $num_hist = param('num_hist');

        my %quote_hashtable = SymbolToHash($symbol);
        my $strike_price = $quote_hashtable{'last'};
        if ($strike_price == "(null)"){
            print "<p>Stock $symbol does not exist.</p>";
            print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
            die;
        }
        else{
            print "<img src=http://murphy.wot.eecs.northwestern.edu/~yhl4722/portfolio/time_series_symbol_project.pl?symbol=$symbol&days=$days&num_hist=$num_hist>";
        }
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return</a></p>";
}



if ($action eq "stock"){
    my $symbol = param('symbol');
    print "<h1>$symbol</h1>";
    my $rsi = RSI($symbol);
    print "<p> RSI (relative strength index) of $symbol according to the data of past 14 open days: $rsi</p>";
    if(!$run) {
        GetPlot($symbol, undef, undef);
        print start_form(-name => "Date Picker"),
                "View Data from (MM/DD/YYYY)", 
                textfield( -name=>'from'),
                "View Data to (MM/DD/YYYY)",
                textfield( -name=>'to'),
                hidden( -name => 'run', -default => ['1'] ),
                hidden( -name => 'act', -default => ['stock'] ),
                hidden( -name => 'symbol', -default => [$symbol]),
                hidden( -name => 'portfolio_id', -default => [$portfolio_id]),
                submit,
                end_form;
       # print "<p><a href=\"portfolio.pl?action=portfolio\"</p>"
    } else {
        my $from = param('from');
        my $to = param('to');
        my $symbol = param('symbol');

        print h2("This is $symbol"),
                h2("From $from"),
                h2("To $to");

        GetPlot($symbol, $from, $to);
        print "<p><a href=\"portfolio.pl?act=stock&symbol=$symbol&portfolio_id=$portfolio_id\">Return to choose another interval</a></p>";
    }
    print "<p><a href=\"portfolio.pl?act=portfolio&run=0&portfolio_id=$portfolio_id\">Return to Portfolio</a></p>";
}

sub RSI {
    my @index_table = undef;
    eval {
        @index_table =
        ExecSQL($dbuser, 
                $dbpasswd,
                "with CHANGE AS (select ((close-open)/open) as VALUE from (select open, close, rank() over (order by timestamp desc) as rnk from stocks WHERE symbol = ?) where rnk <= 14), GAIN AS (SELECT avg(VALUE) as ratio from CHANGE where value > 0), LOSS AS (SELECT -avg(VALUE) as ratio from CHANGE where value < 0) select 100-(100/(1+(select ratio from GAIN)/(select ratio from LOSS))) from DUAL", 
                undef, , 
                @_);
    };
    my $rsi = @index_table ->[0] -> [0];
    return $rsi;
}


if($action eq 'correlation') {
    if(!$run)
   { 
       my $portfolio_id = param('portfolio_id');
       print "<h2> Here is your correlation for your portfolio #$portfolio_id</h2>";
       GetCorMatrix(undef, undef);
       print start_form(-name => "correlation matrix"),
                "View Data from (MM/DD/YYYY)", 
                textfield(-name => "from"),
                "View Data to (MM/DD/YYYY)",
                textfield(-name => "to"),
                hidden( -name => 'act', -default => ['correlation'] ),
                hidden(-name=>'run', -default => ['1']),
                hidden(-name => 'portfolio_id', -default => [$portfolio_id]),
                submit,
                end_form,
                hr;
        print "<p><a href=\"portfolio.pl?act=portfolio&portfolio_id=$portfolio_id\">Return to portfolio</a></p>";
    } else {
        my $portfolio_id = param('portfolio_id');
        my $from = param('from');
        my $to = param('to');

        GetCorMatrix($from, $to);
        print "<p><a href=\"portfolio.pl?act=correlation&portfolio_id=$portfolio_id\">Return</a></p>";
    }
}

######
if ($debug) {
    print hr, p, hr, p, h2('Debugging Output');
    print h3('Parameters');
    print "<menu>";
    print map { "<li>$_ => " . escapeHTML( param($_) ) } param();
    print "</menu>";
    print h3('Cookies');
    print "<menu>";
    print map { "<li>$_ => " . escapeHTML( cookie($_) ) } cookie();
    print "</menu>";
    my $max = $#sqlinput > $#sqloutput ? $#sqlinput : $#sqloutput;
    print h3('SQL');
    print "<menu>";

    for ( my $i = 0 ; $i <= $max ; $i++ ) {
        print "<li><b>Input:</b> " . escapeHTML( $sqlinput[$i] );
        print "<li><b>Output:</b> $sqloutput[$i]";
    }
    print "</menu>";
}


sub GetBeta {
    my @beta_table = undef;
    my $stocksymbol = $_[0];
    eval {
        @beta_table =
        ExecSQL($dbuser, $dbpasswd,
                "select ((select covar_pop(a.close,b.close) from (select close, timestamp from stocks where symbol = ?) a join (select close, timestamp from stocks where symbol = 'SPY') b on a.timestamp = b.timestamp)/(select variance(close) from stocks where symbol = ?)) from DUAL", 
                undef, 
                $stocksymbol, 
                $stocksymbol);
    };
    my $beta = @beta_table ->[0] -> [0];
    return $beta;
}

sub GetCorMatrix {
    my ($from, $to) = @_;
    my @stock_table = FetchStocks($portfolio_id);
    my @stocks;
    foreach my $row (@stock_table) {
        push @stocks, $row->[0];
    }
    # TODO: print and get correlation matrix 

    # my $matrix = `source ./setup_ora.sh; ./get_covar.pl --from=$from --to=$to @stocks `;
    # my @elements = split '\n', $matrix;
    # my $test_string = join "</br>", @elements;
    # $matrix = "<p>".$matrix."</p>";
    # print $test_string;
    my @matrix = `source ./setup_ora.sh; ./get_covar.pl --from=$from --to=$to @stocks `;
    print "<pre>";
        print @matrix;
    print "</pre>";
}

sub GetCoefVar {
    my $symbol = $_[0];
    my $info = `source ./setup_ora.sh; ./get_info.pl $symbol`;
    my @elements = split(' ', $info);
    return pop @elements;
}

sub GetPlot {
    my ($symbol, $from, $to) = @_;
    if (!defined($from)) {
        $from = "01/01/1970";
    }
    if (!defined($to)) {
        $to = "01/01/2030";
    }
    print "<img src=http://murphy.wot.eecs.northwestern.edu/~yhl4722/portfolio/plot_data.pl?type=plot&symbol=$symbol&from=$from&to=$to>";
    
}


sub MakeTable {
    my ( $id, $type, $headerlistref, @list ) = @_;
    my $out;
    #
    # Check to see if there is anything to output
    #
    if ( ( defined $headerlistref ) || ( $#list >= 0 ) ) {

        # if there is, begin a table
        #
        $out = "<table id=\"$id\" border>";
        #
        # if there is a header list, then output it in bold
        #
        if ( defined $headerlistref ) {
            $out .= "<tr>"
              . join( "", ( map { "<td><b>$_</b></td>" } @{$headerlistref} ) )
              . "</tr>";
        }
        #
        # If it's a single row, just output it in an obvious way
        #
        if ( $type eq "ROW" ) {
           #
           # map {code} @list means "apply this code to every member of the list
           # and return the modified list.  $_ is the current list member
           #
            $out .= "<tr>"
              . ( map { defined($_) ? "<td>$_</td>" : "<td>(null)</td>" }
                  @list )
              . "</tr>";
        }
        elsif ( $type eq "COL" ) {
            #
            # ditto for a single column
            #
            $out .= join(
                "",
                map {
                    defined($_)
                      ? "<tr><td>$_</td></tr>"
                      : "<tr><td>(null)</td></tr>"
                } @list
            );
        }
        else {
            #
            # For a 2D table, it's a bit more complicated...
            #
            $out .= join(
                "",
                map { "<tr>$_</tr>" } (
                    map {
                        join(
                            "",
                            map {
                                defined($_)
                                  ? "<td>$_</td>"
                                  : "<td>(null)</td>"
                            } @{$_}
                          )
                    } @list
                )
            );
        }
        $out .= "</table>";
    }
    else {
        # if no header row or list, then just say none.
        $out .= "(none)";
    }
    return $out;
}

#
# Given a list of scalars, or a list of references to lists, generates
# an HTML <pre> section, one line per row, columns are tab-deliminted
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
#
# $html = MakeRaw($id, $type, @list);
#
sub MakeRaw {
    my ( $id, $type, @list ) = @_;
    my $out;
    #
    # Check to see if there is anything to output
    #
    $out = "<pre id=\"$id\">\n";
    #
    # If it's a single row, just output it in an obvious way
    #
    if ( $type eq "ROW" ) {
        #
        # map {code} @list means "apply this code to every member of the list
        # and return the modified list.  $_ is the current list member
        #
        $out .= join( "\t", map { defined($_) ? $_ : "(null)" } @list );
        $out .= "\n";
    }
    elsif ( $type eq "COL" ) {
        #
        # ditto for a single column
        #
        $out .= join( "\n", map { defined($_) ? $_ : "(null)" } @list );
        $out .= "\n";
    }
    else {
        #
        # For a 2D table
        #
        foreach my $r (@list) {
            $out .= join( "\t", map { defined($_) ? $_ : "(null)" } @{$r} );
            $out .= "\n";
        }
    }
    $out .= "</pre>\n";
    return $out;
}

#
# @list=ExecSQL($user, $password, $querystring, $type, @fill);
#
# Executes a SQL statement.  If $type is "ROW", returns first row in list
# if $type is "COL" returns first column.  Otherwise, returns
# the whole result table as a list of references to row lists.
# @fill are the fillers for positional parameters in $querystring
#
# ExecSQL executes "die" on failure.
#
sub ExecSQL {
    my ( $user, $passwd, $querystring, $type, @fill ) = @_;
    if ($debug) {

 # if we are recording inputs, just push the query string and fill list onto the
 # global sqlinput list
        push @sqlinput,
          "$querystring (" . join( ",", map { "'$_'" } @fill ) . ")";
    }
    my $dbh = DBI->connect( "DBI:Oracle:", $user, $passwd );
    if ( not $dbh ) {

       # if the connect failed, record the reason to the sqloutput list (if set)
       # and then die.
        if ($debug) {
            push @sqloutput,
              "<b>ERROR: Can't connect to the database because of "
              . $DBI::errstr . "</b>";
        }
        die "Can't connect to database because of " . $DBI::errstr;
    }
    my $sth = $dbh->prepare($querystring);
    if ( not $sth ) {
        #
        # If prepare failed, then record reason to sqloutput and then die
        #
        if ($debug) {
            push @sqloutput,
              "<b>ERROR: Can't prepare '$querystring' because of "
              . $DBI::errstr . "</b>";
        }
        my $errstr = "Can't prepare $querystring because of " . $DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    if ( not $sth->execute(@fill) ) {
        #
        # if exec failed, record to sqlout and die.
        if ($debug) {
            push @sqloutput,
                "<b>ERROR: Can't execute '$querystring' with fill ("
              . join( ",", map { "'$_'" } @fill )
              . ") because of "
              . $DBI::errstr . "</b>";
        }
        my $errstr =
            "Can't execute $querystring with fill ("
          . join( ",", map { "'$_'" } @fill )
          . ") because of "
          . $DBI::errstr;
        $dbh->disconnect();
        die $errstr;
    }
    #
    # The rest assumes that the data will be forthcoming.
    #
    #
    my @data;
    if ( defined $type and $type eq "ROW" ) {
        @data = $sth->fetchrow_array();
        $sth->finish();
        if ($debug) {
            push @sqloutput,
              MakeTable( "debug_sqloutput", "ROW", undef, @data );
        }
        $dbh->disconnect();
        return @data;
    }
    my @ret;
    while ( @data = $sth->fetchrow_array() ) {
        push @ret, [@data];
    }
    if ( defined $type and $type eq "COL" ) {
        @data = map { $_->[0] } @ret;
        $sth->finish();
        if ($debug) {
            push @sqloutput,
              MakeTable( "debug_sqloutput", "COL", undef, @data );
        }
        $dbh->disconnect();
        return @data;
    }
    $sth->finish();
    if ($debug) {
        push @sqloutput, MakeTable( "debug_sql_output", "2D", undef, @ret );
    }
    $dbh->disconnect();
    return @ret;
}


# The following is necessary so that DBD::Oracle can
# find its butt
#
BEGIN {
    unless ( $ENV{BEGIN_BLOCK} ) {
        use Cwd;
        $ENV{ORACLE_BASE}     = "/raid/oracle11g/app/oracle/product/11.2.0.1.0";
        $ENV{ORACLE_HOME}     = $ENV{ORACLE_BASE} . "/db_1";
        $ENV{ORACLE_SID}      = "CS339";
        $ENV{LD_LIBRARY_PATH} = $ENV{ORACLE_HOME} . "/lib";
        $ENV{BEGIN_BLOCK}     = 1;
        exec 'env', cwd() . '/' . $0, @ARGV;
    }
}

