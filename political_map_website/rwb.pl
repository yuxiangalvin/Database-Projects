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
my $cookiename = "RWBSession";
#
# And another cookie to preserve the debug state
#
my $debugcookiename = "RWBDebug";

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
    ( $user, $password ) = ( "anon", "anonanon" );
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
        ( $user, $password ) = ( "anon", "anonanon" );
    }
}

#
# If we are being asked to log out, then if
# we have a cookie, we should delete it.
#
if ( $action eq "logout" ) {
    $deletecookie = 1;
    $action       = "base";
    $user         = "anon";
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
print "<title>Red, White, and Blue</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

#
# Force device width, for mobile phones, etc
#
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
#
print "<style type=\"text/css\">\n\@import \"rwb.css\";\n</style>\n";

print "<p><b>YOU NEED TO SET DBUSER</b></p>"   if ( $dbuser eq "CHANGEME" );
print "<p><b>YOU NEED TO SET DBPASSWD</b></p>" if ( $dbpasswd eq "CHANGEME" );
print "<p><b>YOU NEED TO SET GOOGLEMAPSKEY</b></p>"
  if ( $googlemapskey eq "CHANGEME" );

print "<center>" if !$debug;

#
#
# The remainder here is essentially a giant switch statement based
# on $action.
#
#
#

# LOGIN
#
# Login is a special case since we handled running the filled out form up above
# in the cookie-handling code.  So, here we only show the form if needed
#
#
if ( $action eq "login" ) {
    if ($logincomplain) {
        print "Login failed.  Try again.<p>";
    }
    if ( $logincomplain or !$run ) {
        print start_form( -name => 'Login' ),
          h2('Login to Red, White, and Blue'),
          "Name:", textfield( -name => 'user' ), p,
          "Password:", password_field( -name => 'password' ), p,
          hidden( -name => 'act', default => ['login'] ),
          hidden( -name => 'run', default => ['1'] ),
          submit,
          end_form;
    }
}

#
# BASE
#
# The base action presents the overall page to the browser
# This is the "document" that the JavaScript manipulates
#
#
if ( $action eq "base" ) {
    #
    # Google maps API, needed to draw the map
    #
    print
"<script src=\"https://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js\" type=\"text/javascript\"></script>";
    if ( $googlemapskey eq "CHANGEME" ) {

        # keyless access - will look hideous and not work right
        print
"<script src=\"https://maps.google.com/maps/api/js\" type=\"text/javascript\"></script>";
    }
    else {
        print
"<script src=\"https://maps.google.com/maps/api/js?key=$googlemapskey\" type=\"text/javascript\"></script>";
    }

    #
    # The Javascript portion of our app
    #
    print "<script type=\"text/javascript\" src=\"rwb.js\"> </script>";

    #
    #
    # And something to color (Red, White, or Blue)
    #
    print "<div id=\"color\" style=\"width:100\%; height:10\%\"></div>";

    #
    #
    # And a map which will be populated later
    #
    print "<div id=\"map\" style=\"width:100\%; height:80\%\"></div>";

    # Checkboxes for FEC data
    print "<div id=\"what_checkbox_division\">";
    print "<p>You can select from the following categories: </p>";
    print
"<input type=\"checkbox\" ID=\"Committee\" value=\"Committee\"> Committee<br>";
    print
"<input type=\"checkbox\" ID=\"Candidate\" value=\"Candidate\"> Candidate<br>";
    print
"<input type=\"checkbox\" ID=\"Individual\" value=\"Individual\"> Individual<br>";
    print
      "<input type=\"checkbox\" ID=\"Opinion\" value=\"Opinion\"> Opinion<br>";
    print "</div>";

    print "<p>You can choose from the following cycles: </p>";
    my $formcycle       = "allCycles";
    my $cycleCheckboxes = CreateCheckboxes(
        $formcycle,
        ExecSQL(
            $dbuser,
            $dbpasswd,
"select distinct cycle from cs339.committee_master UNION select distinct cycle from cs339.candidate_master UNION select distinct cycle from cs339.individual",
            undef
        )
    );
    print "<div id=\"cycle_checkbox_division\">";
    print $cycleCheckboxes;
    print "</div>";

    print
      "<button id=\"submit_button\" onClick=\"ViewShift()\">Submit</button>";

    

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

    #
    # User mods
    #
    #
    if ( $user eq "anon" ) {
        print
"<p>You are anonymous, but you can also <a href=\"rwb.pl?act=login\">login</a></p>";
    }
    else {
        print "<p>You are logged in as $user and can do the following:</p>";

        if ( UserCan( $user, "give-opinion-data" ) ) {
            print
"<p><a id=\"give_opinion\">Give Opinion Of Current Location</a></p>";
        }
        if ( UserCan( $user, "give-cs-ind-data" ) ) {
            print
"<p><a href=\"rwb.pl?act=give-cs-ind-data\">Geolocate Individual Contributors</a></p>";
        }
        if (   UserCan( $user, "manage-users" )
            || UserCan( $user, "invite-users" ) )
        {
            print "<p><a href=\"rwb.pl?act=invite-user\">Invite User</a></p>";
        }
        if ( UserCan( $user, "manage-users" ) || UserCan( $user, "add-users" ) )
        {
            print "<p><a href=\"rwb.pl?act=add-user\">Add User</a></p>";
        }
        if ( UserCan( $user, "manage-users" ) ) {
            print "<p><a href=\"rwb.pl?act=delete-user\">Delete User</a></p>";
            print
"<p><a href=\"rwb.pl?act=add-perm-user\">Add User Permission</a></p>";
            print
"<p><a href=\"rwb.pl?act=revoke-perm-user\">Revoke User Permission</a></p>";
        }
        print "<p><a href=\"rwb.pl?act=logout&run=1\">Logout</a></p>";
    }

    print "<div id=\"summary_comm\" style=\"width:100\%; height:10\%\"></div>";
    print "<div id=\"summary_cand\" style=\"width:100\%; height:10\%\"></div>";
    print "<div id=\"summary_ind\" style=\"width:100\%; height:10\%\"></div>";
    print "<div id=\"summary_op\" style=\"width:100\%; height:10\%\"></div>";
}

#
#
# NEAR
#
#
# Nearby committees, candidates, individuals, and opinions
#
#
# Note that the individual data should integrate the FEC data and the more
# precise crowd-sourced location data.   The opinion data is completely crowd-sourced
#
# This form intentionally avoids decoration since the expectation is that
# the client-side javascript will invoke it to get raw data for overlaying on the map
#
#
if ( $action eq "near" ) {
    my $latne     = param("latne");
    my $longne    = param("longne");
    my $latsw     = param("latsw");
    my $longsw    = param("longsw");
    my $whatparam = param("what");
    my $format    = param("format");
    my $cycle     = param("cycle");
    my %what;

    $format = "table" if !defined($format);
    $cycle  = "1112"  if !defined($cycle);

    my @cycles = split( ',', $cycle );

    # $cycle = '(\'' .join(',',@cycles) . '\')';

    if ( !defined($whatparam) || $whatparam eq "all" ) {
        %what = (
            committees  => 1,
            candidates  => 1,
            individuals => 1,
            opinions    => 1
        );
    }
    else {
        map { $what{$_} = 1 } split( /\s*,\s*/, $whatparam );
    }

    if ( $what{committees} ) {
        my ( $str, $error ) =
          Committees( $latne, $longne, $latsw, $longsw, $cycle, $format );
        if ( !$error ) {
            if ( $format eq "table" ) {
                print "<h2>Nearby committees</h2>$str";
            }
            else {
                print $str;
            }
        }

        #Aggregate View
        my @comm_to_comm_count;
        my @comm_to_cand_count;
        eval {
            @comm_to_comm_count = ExecSQL(
                $dbuser,
                $dbpasswd,
"select count(*) from cs339.comm_to_comm natural join cs339.cmte_id_to_geo where cycle in "
                  . $cycle
                  . " and latitude>? and latitude<? and longitude>? and longitude<?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
            @comm_to_cand_count = ExecSQL(
                $dbuser,
                $dbpasswd,
"select count(*) from cs339.comm_to_cand natural join cs339.cmte_id_to_geo where cycle in "
                  . $cycle
                  . " and latitude>? and latitude<? and longitude>? and longitude<?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
        };
        ###### Potential Bug
        my $comm_transfer_count =
          $comm_to_comm_count[0][0] + $comm_to_cand_count[0][0];

        while ( $comm_transfer_count < 3 ) {
            $latne  = $latne + 0.05;
            $longne = $longne + 0.05;
            $latsw  = $latsw - 0.05;
            $longsw = $longsw - 0.05;

            eval {
                @comm_to_comm_count = ExecSQL(
                    $dbuser,
                    $dbpasswd,
"select count(*) from cs339.comm_to_comm natural join cs339.cmte_id_to_geo where cycle in "
                      . $cycle
                      . " and latitude>? and latitude<? and longitude>? and longitude<?",
                    undef,
                    $latsw,
                    $latne,
                    $longsw,
                    $longne
                );
                @comm_to_cand_count = ExecSQL(
                    $dbuser,
                    $dbpasswd,
"select count(*) from cs339.comm_to_cand natural join cs339.cmte_id_to_geo where cycle in "
                      . $cycle
                      . " and latitude>? and latitude<? and longitude>? and longitude<?",
                    undef,
                    $latsw,
                    $latne,
                    $longsw,
                    $longne
                );
            };

            $comm_transfer_count =
              $comm_to_comm_count[0][0] + $comm_to_cand_count[0][0];
        }

        print "<div id='comm_transfer_summary'>";

        my ( $democ_comm_comm_amount_str, $error_1 ) =
          SelectDemocCommComm( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_1 ) {
            if ( $format eq "table" ) {
                print
"<h2>Democratic Committee to Committee Transfer Amount</h2> $democ_comm_comm_amount_str";
            }
            else {
                print
                  "<h2>Democratic Committee to Committee Transfer Amount</h2>";
                print $democ_comm_comm_amount_str;
            }
        }

        my ( $repub_comm_comm_amount_str, $error_2 ) =
          SelectRepubCommComm( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_2 ) {
            if ( $format eq "table" ) {
                print
"<h2>Republic Committee to Committee Transfer Amount</h2> $democ_comm_comm_amount_str";
            }
            else {
                print
                  "<h2>Republic Committee to Committee Transfer Amount</h2>";
                print $repub_comm_comm_amount_str;
            }
        }

        my ( $democ_comm_cand_amount_str, $error_3 ) =
          SelectDemocCommCand( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_3 ) {
            if ( $format eq "table" ) {
                print
"<h2>Democratic Committee to Candidate Transfer Amount</h2> $democ_comm_cand_amount_str";
            }
            else {
                print
                  "<h2>Democratic Committee to Candidate Transfer Amount</h2>";
                print $democ_comm_cand_amount_str;
            }
        }

        my ( $repub_comm_cand_amount_str, $error_4 ) =
          SelectRepubCommCand( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_4 ) {
            if ( $format eq "table" ) {
                print
"<h2>Republic Committee to Candidate Transfer Amount</h2> $repub_comm_cand_amount_str";
            }
            else {
                print
                  "<h2>Republic Committee to Candidate Transfer Amount</h2>";
                print $repub_comm_cand_amount_str;
            }
        }

    }

    print "</div>";
    if ( $what{candidates} ) {
        my ( $str, $error_5 ) =
          Candidates( $latne, $longne, $latsw, $longsw, $cycle, $format );
        if ( !$error_5 ) {
            if ( $format eq "table" ) {
                print "<h2>Nearby candidates</h2>$str";
            }
            else {
                print $str;
            }
        }
    }

    if ( $what{individuals} ) {
        my ( $str, $error_6 ) =
          Individuals( $latne, $longne, $latsw, $longsw, $cycle, $format );
        if ( !$error_6 ) {
            if ( $format eq "table" ) {
                print "<h2>Nearby individuals</h2>$str";
            }
            else {
                print $str;
            }
        }

        #Aggregate View
        my @ind_tran_count_arr = ();
        eval {
            @ind_tran_count_arr = ExecSQL(
                $dbuser,
                $dbpasswd,
"select count(*) from cs339.individual natural join (select * from cs339.ind_to_geo where latitude>? and latitude<? and longitude>? and longitude<?) where cycle in "
                  . $cycle . "",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
        };

        my $ind_tran_count = $ind_tran_count_arr[0][0];

        while ( $ind_tran_count < 3 ) {
            $latne  = $latne + 0.05;
            $longne = $longne + 0.05;
            $latsw  = $latsw - 0.05;
            $longsw = $longsw - 0.05;

            eval {
                @ind_tran_count_arr = ExecSQL(
                    $dbuser,
                    $dbpasswd,
"select count(*) from cs339.individual natural join (select * from cs339.ind_to_geo where latitude>? and latitude<? and longitude>? and longitude<?) where cycle in "
                      . $cycle . "",
                    undef,
                    $latsw,
                    $latne,
                    $longsw,
                    $longne
                );
            };

            $ind_tran_count = $ind_tran_count_arr[0][0];
        }

        print "<div id='ind_transfer_summary'>";

        my ( $democ_ind_tran_amount_str, $error_7 ) =
          SelectDemocIndTranAmount( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_7 ) {
            if ( $format eq "table" ) {
                print "<h2>Democratic Indiviual Transfer Amount</h2> $democ_ind_tran_amount_str";
            }
            else {
                print "<h2>Democratic Indiviual Transfer Amount</h2>";
                print $democ_ind_tran_amount_str;
            }
        }

        my ( $repub_ind_tran_amount_str, $error_1_0) = 
          SelectRepubIndTranAmount( $latne, $longne, $latsw, $longsw, $cycle, $format);
        if ( !$error_1_0) {
            if ( $format eq "table") {
                print "<h2>Republican Indiviual Transfer Amount</h2> $repub_ind_tran_amount_str";
            }
            else {
                print "<h2>Republican Indiviual Transfer Amount</h2>";
                print $repub_ind_tran_amount_str;
            }
        }
        print "</div>";
    }

    if ( $what{opinions} ) {
        my ( $str, $error_8 ) =
          Opinions( $latne, $longne, $latsw, $longsw, $cycle, $format );
        if ( !$error_8 ) {
            if ( $format eq "table" ) {
                print "<h2>Nearby opinions</h2>$str";
            }
            else {
                print $str;
            }
        }

        #Aggregate View
        my @opinion_color_arr = ();
        eval {
            @opinion_color_arr = ExecSQL(
                $dbuser,
                $dbpasswd,
"select count(*) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
                undef,
                $latsw,
                $latne,
                $longsw,
                $longne
            );
        };
        my $opinion_color_count = $opinion_color_arr[0][0];

        while ( $opinion_color_count < 3 ) {
            $latne  = $latne + 0.05;
            $longne = $longne + 0.05;
            $latsw  = $latsw - 0.05;
            $longsw = $longsw - 0.05;

            eval {
                @opinion_color_arr = ExecSQL(
                    $dbuser,
                    $dbpasswd,
"select count(*) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
                    undef,
                    $latsw,
                    $latne,
                    $longsw,
                    $longne
                );
            };

            $opinion_color_count = @{ $opinion_color_arr[0] }[0];
        }

        print "<div id='opinion_color_summary'>";

        my ( $opinion_color_str, $error_9 ) =
          SelectOpinionColor( $latne, $longne, $latsw, $longsw, $cycle,
            $format );
        if ( !$error_9 ) {
            if ( $format eq "table" ) {
                print
"<h2>Opinion Color Statistics Summary</h2> $opinion_color_str";
            }
            else {
                print "<h2>Opinion Color Statistics Summary</h2>";
                print $opinion_color_str;
            }
        }
        print "</div>";
    }
}

sub SelectDemocCommComm {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @democ_comm_comm_amount_arr = ();
    eval {
        @democ_comm_comm_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.comm_to_comm natural join cs339.cmte_id_to_geo where cycle in "
              . $cycle
              . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='DEM')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "democ_comm_comm_amount", "2D",
                    ["Democratic Committee to Committe Transfer Amount"],
                    @democ_comm_comm_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "democ_comm_comm_amount", "2D",
                    @democ_comm_comm_amount_arr
                ),
                $@
            );
        }
    }
}

sub SelectRepubCommComm {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @repub_comm_comm_amount_arr = ();
    eval {
        @repub_comm_comm_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.comm_to_comm natural join cs339.cmte_id_to_geo where cycle in "
              . $cycle
              . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='REP')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    # print "<h2>HA</h2>";
    # if(@repub_comm_comm_amount_arr){
    #   print "<h2>bug</h2>";

    #   foreach (@repub_comm_comm_amount_arr) {
    #     foreach (@_) {
    #       print "$_\n";
    #     }
    #     print "$_\n";
    #   }

    #   @repub_comm_comm_amount_arr  = 0;
    # }

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "repub_comm_comm_amount", "2D",
                    ["Republican Committee to Committe Transfer Amount"],
                    @repub_comm_comm_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "repub_comm_comm_amount", "2D",
                    @repub_comm_comm_amount_arr
                ),
                $@
            );
        }
    }
}

sub SelectDemocCommCand {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @democ_comm_cand_amount_arr;
    eval {
        @democ_comm_cand_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.comm_to_cand natural join cs339.cmte_id_to_geo where cycle in "
              . $cycle
              . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='DEM')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "democ_comm_cand_amount", "2D",
                    ["Democratic Committee to Candidate Transfer Amount"],
                    @democ_comm_cand_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "democ_comm_cand_amount", "2D",
                    @democ_comm_cand_amount_arr
                ),
                $@
            );
        }
    }
}

sub SelectRepubCommCand {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @repub_comm_cand_amount_arr = ();
    eval {
        @repub_comm_cand_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.comm_to_cand natural join cs339.cmte_id_to_geo where cycle in "
              . $cycle
              . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='REP')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "repub_comm_cand_amount", "2D",
                    ["Republican Committee to Candidate Transfer Amount"],
                    @repub_comm_cand_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "repub_comm_cand_amount", "2D",
                    @repub_comm_cand_amount_arr
                ),
                $@
            );
        }
    }
}

sub SelectRepubIndTranAmount {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @repub_ind_tran_amount_arr = ();
    eval {
        @repub_ind_tran_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.individual natural join cs339.ind_to_geo where cycle in "
              . $cycle . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='REP')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "repub_ind_tran_amount_summary",      "2D",
                    ["Republican Individual Transfer Amount"], @repub_ind_tran_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "repub_ind_tran_amount_summary", "2D", @repub_ind_tran_amount_arr
                ),
                $@
            );
        }
    }
}

sub SelectDemocIndTranAmount {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @democ_ind_tran_amount_arr = ();
    eval {
        @democ_ind_tran_amount_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select sum(TRANSACTION_AMNT) from cs339.individual natural join cs339.ind_to_geo where cycle in "
              . $cycle . " and latitude>? and latitude<? and longitude>? and longitude<? and CMTE_ID in (select CMTE_ID from cs339.committee_master where CMTE_PTY_AFFILIATION='DEM')",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "democ_ind_tran_amount_summary",      "2D",
                    ["Democratic Individual Transfer Amount"], @democ_ind_tran_amount_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "democ_ind_tran_amount_summary", "2D", @democ_ind_tran_amount_arr
                ),
                $@
            );
        }
    }
}

# sub SelectIndTranAmount {
#     my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
#     my @ind_tran_amount_arr = ();
#     eval {
#         @ind_tran_amount_arr = ExecSQL(
#             $dbuser,
#             $dbpasswd,
# "select sum(TRANSACTION_AMNT) from cs339.individual natural join (select * from cs339.ind_to_geo where latitude>? and latitude<? and longitude>? and longitude<?) where cycle in "
#               . $cycle . "",
#             undef,
#             $latsw,
#             $latne,
#             $longsw,
#             $longne
#         );
#     };

#     if ($@) {
#         return ( undef, $@ );
#     }
#     else {
#         if ( $format eq "table" ) {
#             return (
#                 MakeTable(
#                     "ind_tran_amount_summary",      "2D",
#                     ["Individual Transfer Amount"], @ind_tran_amount_arr
#                 ),
#                 $@
#             );
#         }
#         else {
#             return (
#                 MakeRaw(
#                     "ind_tran_amount_summary", "2D", @ind_tran_amount_arr
#                 ),
#                 $@
#             );
#         }
#     }
# }

sub SelectOpinionColor {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @opinion_color_stats_arr = ();
    eval {
        @opinion_color_stats_arr = ExecSQL(
            $dbuser,
            $dbpasswd,
"select avg(color), stddev(color) from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };
    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "opinion_color_stats_summary", "2D",
                    ["Opinion Color Statistics"],  @opinion_color_stats_arr
                ),
                $@
            );
        }
        else {
            return (
                MakeRaw(
                    "opinion_color_stats_summary", "2D",
                    @opinion_color_stats_arr
                ),
                $@
            );
        }
    }
}

if ( $action eq "create-account" ) {
    my @uuid_exist;
    my $id = param('unique-id');
    eval {
        @uuid_exist =
          ExecSQL( $dbuser, $dbpasswd,
            "select count(*) from invited_users where uuid=?",
            undef, $id );
    };
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
        if ( registeredInviteKey($id) == 1 ) {
            print h2('Your link has been used.');
            return;
        }
        ## check if the uuid exists, if not, print warning message
        # query invited_users table

        if ( $uuid_exist[0][0] == 0 ) {
            print h2('Your link is invalid.');
            return;

        }
        print start_form( -name => 'CreateAccount' ),
          h2('Create your account here'),
          "Name: ",     textfield( -name => 'name' ),     p,
          "Email: ",    textfield( -name => 'email' ),    p,
          "Password: ", textfield( -name => 'password' ), p,
          hidden( -name => 'run',       -default => ['1'] ),
          hidden( -name => 'act',       -default => ['create-account'] ),
          hidden( -name => 'unique-id', -default => [$id] ),
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
        my @ref;
        eval {
            @ref =
              ExecSQL( $dbuser, $dbpasswd,
                "select referer from invited_users where uuid=?",
                undef, $id );
        };
        my $error;
        $error = UserAdd( $name, $pw, $email, $ref[0][0] );
        if ($error) {
            print "Can't create account because: $error";
        }
        else {
            ## grant permissions to users
            # query permissions from the invited_users table
            my @granted_permissions;
            eval {
                @granted_permissions =
                  ExecSQL( $dbuser, $dbpasswd,
                    "select action from invited_permissions where uuid=?",
                    'COL', $id );
            };

            # store granted permissions in the rwb_permissions table
            foreach (@granted_permissions) {
                eval {
                    ExecSQL( $dbuser, $dbpasswd,
                        "insert into rwb_permissions values(\'$name\', \'$_\')"
                    );
                };
            }

            # mark the registered flag as 1 in the invited_users table
            eval {
                ExecSQL( $dbuser, $dbpasswd,
                    "update invited_users set registered=1 where uuid=?",
                    undef, $id );
            };

            # print success message
            print "You have successfully created your account.";
            print
"Created user $name with email $email as referred by $ref[0][0] \n";
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

## Part 2: give opinion data

if ( $action eq "give-opinion-data" ) {

    # print h2("Giving Location Opinion Data Is Unimplemented");
    # assign a political "color" to the user's corrent location
    if ( !UserCan( $user, "give-opinion-data" ) ) {
        print h2('You do not have the required permissions to give opinions.');
    }
    else {
        if ( !$run ) {

            # create a hash table for opinion labels
            my %opinion_labels = (
                '-1' => 'Red',
                '0'  => 'White',
                '1'  => 'Blue',
            );
            print start_form( -name => 'give_opinion' ), h2('Give Opinion'),
              radio_group(
                -name      => 'user-opinion',
                -values    => [ '-1', '0', '1' ],
                -default   => '0',
                -linebreak => 'true',
                -labels    => \%opinion_labels
              ),
              p,
              hidden(
                -name    => 'longitude',
                -default => [ param('longitude') ]
              ),
              hidden( -name => 'latitude', -default => [ param('latitude') ] ),
              hidden( -name => 'act',      -default => ['give-opinion-data'] ),
              hidden( -name => 'run',      -default => ["1"] ),
              submit,
              end_form,
              end_html;
        }
        else {
            # what values should $useropinioncolor, $lat, $long be set to
            # my $useropinioncolor;
            # my $error;
            # my $lat;
            # my $long;
            # if ($error) {
            #   print "Can't give your opinion because: $error";
            # }
            # else {
            # put the "color" info into the rwb_opinion table
            my $lat                      = param("latitude");
            my $long                     = param("longitude");
            my $selected_color           = param("user-opinion");
            my @if_user_geo_record_exist = ();
            eval {
                @if_user_geo_record_exist = ExecSQL(
                    $dbuser,
                    $dbpasswd,
"select count(*) from rwb_opinions where submitter=? and latitude=? and longitude=?",
                    undef,
                    $user,
                    $lat,
                    $long
                );
            };
            if ( $if_user_geo_record_exist[0][0] == 0 ) {
                eval {
                    ExecSQL(
                        $dbuser,
                        $dbpasswd,
"insert into rwb_opinions (submitter,color,latitude,longitude) values (?,?,?,?)",
                        undef,
                        $user,
                        $selected_color,
                        $lat,
                        $long
                    );
                };
            }
            else {
                eval {
                    ExecSQL(
                        $dbuser,
                        $dbpasswd,
"update rwb_opinions set color=? where submitter=? and latitude=? and longitude=?",
                        undef,
                        $selected_color,
                        $user,
                        $lat,
                        $long
                      ),
                      ;
                };
            }
            print "You have successfully submitted your opinion.";

            # }
        }
        print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
    }

#print "<form id=\"give_opinion_form\">";
#print "<input type=\"radio\" name=\"opinion\" value=1 id=\"opinion_blue\" checked> Blue <br>";
#print "<input type=\"radio\" name=\"opinion\" value=0 id=\"opinion_white\"> White <br>";
#print "<input type=\"radio\" name=\"opinion\" value=-1 id=\"opinion_red\"> Red <br>";
#print "</form>";
#print "<button id=\"submit_opinion_button\" onClick=\"SubmitOpinion()\">Submit Opinion</button>";
#print "<button onclick=\"location.href='http://murphy.wot.eecs.northwestern.edu/~yhl4722/rwb/rwb.pl?'\"> Return <br>";

}

if ( $action eq "give-cs-ind-data" ) {
    print h2("Giving Crowd-sourced Individual Geolocations Is Unimplemented");
}

#
# INVITE-USER
#
# User Invite functionality
#
#
#
#
if ( $action eq "invite-user" ) {
    if ( !UserCan( $user, "invite-users" ) ) {
        print h2('You do not have the required permissions to invite users.');
    }
    else {
        if ( !$run ) {
            my @user_permissions = ();
            eval {
                @user_permissions =
                  ExecSQL( $dbuser, $dbpasswd,
                    "select ACTION from rwb_permissions where name=?",
                    "COL", $user );
            };
            print start_form( -name => 'InviteUser' ), h2('Invite User'),
              "Email: ", textfield( -name => 'email' ), p,
              hidden( -name => 'run', -default => ['1'] ),
              hidden( -name => 'act', -default => ['invite-user'] ),
              h5(
'Please select what permissions you wish to grant to this invited user:'
              ),
              checkbox_group(
                -name   => 'userPermissions',
                -values => \@user_permissions
              ),
              submit, end_form, hr;

#my $userPermissionCheckboxes = CreateCheckboxes($formPermissions, @user_permissions);
#print "<div id=\"userPermissions_checkbox_division\">";
#print "Please select what permissions you wish to grant to this invited user:\n";
#print $userPermissionCheckboxes;
#print "</div>";
        }
        else {
            my $email = param('email');
            my $error;
            my @new_user_permissions = param('userPermissions');
            if ($error) {
                print "Can't invite user because: $error";
            }
            else {
                # Create a link for the invited user
                ## generate a random number
                my $alpha_string;
                do {
                    my @alpha = ( "A" .. "Z", "a" .. "z", 1 .. 9 );
                    $alpha_string .= $alpha[ rand @alpha ] for 1 .. 8;
                } while ( ConfirmUniqueInviteKey($alpha_string) != 0 );
                ## append the random number to the general link
                # bug-potential: not sure if the link is correct
                my $link =
"http://murphy.wot.eecs.northwestern.edu/~yhl4722/rwb/rwb.pl?act=create-account&unique-id=$alpha_string";
                ### remember to store this link to the dict when
                ### the invited user created account in the
                ### accept-invite function
                # Display permissions with checkboxes
                ## query user permissions
# bug-potential: do we need "COL"
# my @user_permissions = undef;
# eval {@user_permissions= ExecSQL($dbuser,$dbpasswd, "select * from rwb_permissions where name=?","COL",$user);};
# my $formPermissions = "userPermissions";
# my $userPermissionCheckboxes = CreateCheckboxes($formPermissions, @user_permissions);
# print "<div id=\"userPermissions_checkbox_division\">";
# print "Please select what permissions you wish to grant to this invited user:\n";
# print $userPermissionCheckboxes;
# print "</div>";
# my $referer=param($user)
# Send an email with the link to the invited user
                ## bug-potential: may not refer to link in the correct way
                SendEmail( $link, $email, $user );
                ## store invited user's email, uuid, referer, granted permissions in invited_users table
                ## bug-potential: the correct way to pass in an array?
                eval {
                    ExecSQL( $dbuser, $dbpasswd,
                        "INSERT INTO invited_users values (?,?,?,?)",
                        undef, $email, $alpha_string, '0', $user, );
                };

                foreach my $permission (@new_user_permissions) {
                    eval {
                        ExecSQL(
                            $dbuser,
                            $dbpasswd,
                            "INSERT INTO invited_permissions VALUES (?, ?)",
                            undef,
                            $alpha_string,
                            $permission
                        );
                    };
                }

                print "Invited user $email as referred by $user\n";
            }
            print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
        }
    }
}

#
# ADD-USER
#
# User Add functionaltiy
#
#
#
#
if ( $action eq "add-user" ) {
    if ( !UserCan( $user, "add-users" ) && !UserCan( $user, "manage-users" ) ) {
        print h2('You do not have the required permissions to add users.');
    }
    else {
        if ( !$run ) {
            print start_form( -name => 'AddUser' ), h2('Add User'),
              "Name: ",     textfield( -name => 'name' ),     p,
              "Email: ",    textfield( -name => 'email' ),    p,
              "Password: ", textfield( -name => 'password' ), p,
              hidden( -name => 'run', -default => ['1'] ),
              hidden( -name => 'act', -default => ['add-user'] ),
              submit,
              end_form,
              hr;
        }
        else {
            my $name     = param('name');
            my $email    = param('email');
            my $password = param('password');
            my $error;
            $error = UserAdd( $name, $password, $email, $user );
            if ($error) {
                print "Can't add user because: $error";
            }
            else {
                print "Added user $name $email as referred by $user\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# DELETE-USER
#
# User Delete functionaltiy
#
#
#
#
if ( $action eq "delete-user" ) {
    if ( !UserCan( $user, "manage-users" ) ) {
        print h2('You do not have the required permissions to delete users.');
    }
    else {
        if ( !$run ) {
            #
            # Generate the add form.
            #
            print start_form( -name => 'DeleteUser' ), h2('Delete User'),
              "Name: ", textfield( -name => 'name' ), p,
              hidden( -name => 'run', -default => ['1'] ),
              hidden( -name => 'act', -default => ['delete-user'] ),
              submit,
              end_form,
              hr;
        }
        else {
            my $name = param('name');
            my $error;
            $error = UserDel($name);
            if ($error) {
                print "Can't delete user because: $error";
            }
            else {
                print "Deleted user $name\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# ADD-PERM-USER
#
# User Add Permission functionaltiy
#
#
#
#
if ( $action eq "add-perm-user" ) {
    if ( !UserCan( $user, "manage-users" ) ) {
        print h2(
'You do not have the required permissions to manage user permissions.'
        );
    }
    else {
        if ( !$run ) {
            #
            # Generate the add form.
            #
            print start_form( -name => 'AddUserPerm' ),
              h2('Add User Permission'),
              "Name: ", textfield( -name => 'name' ),
              "Permission: ", textfield( -name => 'permission' ), p,
              hidden( -name => 'run', -default => ['1'] ),
              hidden( -name => 'act', -default => ['add-perm-user'] ),
              submit,
              end_form,
              hr;
            my ( $table, $error );
            ( $table, $error ) = PermTable();
            if ( !$error ) {
                print "<h2>Available Permissions</h2>$table";
            }
        }
        else {
            my $name  = param('name');
            my $perm  = param('permission');
            my $error = GiveUserPerm( $name, $perm );
            if ($error) {
                print "Can't add permission to user because: $error";
            }
            else {
                print "Gave user $name permission $perm\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# REVOKE-PERM-USER
#
# User Permission Revocation functionaltiy
#
#
#
#
if ( $action eq "revoke-perm-user" ) {
    if ( !UserCan( $user, "manage-users" ) ) {
        print h2(
'You do not have the required permissions to manage user permissions.'
        );
    }
    else {
        if ( !$run ) {
            #
            # Generate the add form.
            #
            print start_form( -name => 'RevokeUserPerm' ),
              h2('Revoke User Permission'),
              "Name: ", textfield( -name => 'name' ),
              "Permission: ", textfield( -name => 'permission' ), p,
              hidden( -name => 'run', -default => ['1'] ),
              hidden( -name => 'act', -default => ['revoke-perm-user'] ),
              submit,
              end_form,
              hr;
            my ( $table, $error );
            ( $table, $error ) = PermTable();
            if ( !$error ) {
                print "<h2>Available Permissions</h2>$table";
            }
        }
        else {
            my $name  = param('name');
            my $perm  = param('permission');
            my $error = RevokeUserPerm( $name, $perm );
            if ($error) {
                print "Can't revoke permission from user because: $error";
            }
            else {
                print "Revoked user $name permission $perm\n";
            }
        }
    }
    print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
#
#
#
# Debugging output is the last thing we show, if it is set
#
#
#
#

print "</center>" if !$debug;

#
# Generate debugging output if anything is enabled.
#
#
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

print end_html;

#
# The main line is finished at this point.
# The remainder includes utilty and other functions
#

#
# Generate a table of nearby committees
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Committees {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @rows;
    eval {
        @rows = ExecSQL(
            $dbuser,
            $dbpasswd,
"select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle in "
              . $cycle
              . " and latitude>? and latitude<? and longitude>? and longitude<?",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );

#  @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",undef,$cycle,$latsw,$latne,$longsw,$longne);

    };

    if ($@) {
        print "<h1 id=\"execsql-returns-error\"></h1>";
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            print "<h1 id=\"print-table\"></h1>";
            return (
                MakeTable(
                    "committee_data",
                    "2D",
                    [
                        "latitude", "longitude", "name", "party",
                        "street1",  "street2",   "city", "state",
                        "zip"
                    ],
                    @rows
                ),
                $@
            );
        }
        else {
            return ( MakeRaw( "committee_data", "2D", @rows ), $@ );
        }
    }
}

#
# Generate a table of nearby candidates
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Candidates {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @rows;
    eval {
        @rows = ExecSQL(
            $dbuser,
            $dbpasswd,
"select latitude, longitude, cand_name, cand_pty_affiliation, cand_st1, cand_st2, cand_city, cand_st, cand_zip from cs339.candidate_master natural join cs339.cand_id_to_geo where cycle in $cycle and latitude>? and latitude<? and longitude>? and longitude<?",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "candidate_data",
                    "2D",
                    [
                        "latitude", "longitude", "name", "party",
                        "street1",  "street2",   "city", "state",
                        "zip"
                    ],
                    @rows
                ),
                $@
            );
        }
        else {
            return ( MakeRaw( "candidate_data", "2D", @rows ), $@ );
        }
    }
}

#
# Generate a table of nearby individuals
#
# Note that the handout version does not integrate the crowd-sourced data
#
# ($table|$raw,$error) = Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Individuals {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @rows;
    eval {
        @rows = ExecSQL(
            $dbuser,
            $dbpasswd,
"select latitude, longitude, name, city, state, zip_code, employer, transaction_amnt from cs339.individual natural join cs339.ind_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",
            undef,
            $cycle,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "individual_data",
                    "2D",
                    [
                        "latitude", "longitude", "name",     "city",
                        "state",    "zip",       "employer", "amount"
                    ],
                    @rows
                ),
                $@
            );
        }
        else {
            return ( MakeRaw( "individual_data", "2D", @rows ), $@ );
        }
    }
}

#
# Generate a table of nearby opinions
#
# ($table|$raw,$error) = Opinions(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Opinions {
    my ( $latne, $longne, $latsw, $longsw, $cycle, $format ) = @_;
    my @rows;
    eval {
        @rows = ExecSQL(
            $dbuser,
            $dbpasswd,
"select latitude, longitude, color from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",
            undef,
            $latsw,
            $latne,
            $longsw,
            $longne
        );
    };

    if ($@) {
        return ( undef, $@ );
    }
    else {
        if ( $format eq "table" ) {
            return (
                MakeTable(
                    "opinion_data",
                    "2D",
                    [
                        "latitude", "longitude", "name",     "city",
                        "state",    "zip",       "employer", "amount"
                    ],
                    @rows
                ),
                $@
            );
        }
        else {
            return ( MakeRaw( "opinion_data", "2D", @rows ), $@ );
        }
    }
}

#
# Generate a table of available permissions
# ($table,$error) = PermTable()
# $error false on success, error string on failure
#
sub PermTable {
    my @rows;
    eval {
        @rows = ExecSQL( $dbuser, $dbpasswd, "select action from rwb_actions" );
    };
    if ($@) {
        return ( undef, $@ );
    }
    else {
        return ( MakeTable( "perm_table", "2D", ["Perm"], @rows ), $@ );
    }
}

#
# Generate a table of users
# ($table,$error) = UserTable()
# $error false on success, error string on failure
#
sub UserTable {
    my @rows;
    eval {
        @rows = ExecSQL( $dbuser, $dbpasswd,
            "select name, email from rwb_users order by name" );
    };
    if ($@) {
        return ( undef, $@ );
    }
    else {
        return ( MakeTable( "user_table", "2D", [ "Name", "Email" ], @rows ),
            $@ );
    }
}

#
# Generate a table of users and their permissions
# ($table,$error) = UserPermTable()
# $error false on success, error string on failure
#
sub UserPermTable {
    my @rows;
    eval {
        @rows = ExecSQL( $dbuser, $dbpasswd,
"select rwb_users.name, rwb_permissions.action from rwb_users, rwb_permissions where rwb_users.name=rwb_permissions.name order by rwb_users.name"
        );
    };
    if ($@) {
        return ( undef, $@ );
    }
    else {
        return (
            MakeTable(
                "userperm_table", "2D", [ "Name", "Permission" ], @rows
            ),
            $@
        );
    }
}

#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
#
# UserAdd($name,$password,$email)
#
sub UserAdd {
    eval {
        ExecSQL(
            $dbuser,
            $dbpasswd,
"insert into rwb_users (name,password,email,referer) values (?,?,?,?)",
            undef,
            @_
        );
    };
    return $@;
}

#
# Delete a user
# returns false on success, $error string on failure
#
sub UserDel {
    eval {
        ExecSQL( $dbuser, $dbpasswd, "delete from rwb_users where name=?",
            undef, @_ );
    };
    return $@;
}

#
# Give a user a permission
#
# returns false on success, error string on failure.
#
# GiveUserPerm($name,$perm)
#
sub GiveUserPerm {
    eval {
        ExecSQL( $dbuser, $dbpasswd,
            "insert into rwb_permissions (name,action) values (?,?)",
            undef, @_ );
    };
    return $@;
}

#
# Revoke a user's permission
#
# returns false on success, error string on failure.
#
# RevokeUserPerm($name,$perm)
#
sub RevokeUserPerm {
    eval {
        ExecSQL( $dbuser, $dbpasswd,
            "delete from rwb_permissions where name=? and action=?",
            undef, @_ );
    };
    return $@;
}

#
#
# Check to see if user and password combination exist
#
# $ok = ValidUser($user,$password)
#
#
sub ValidUser {
    my ( $user, $password ) = @_;
    my @col;
    eval {
        @col =
          ExecSQL( $dbuser, $dbpasswd,
            "select count(*) from rwb_users where name=? and password=?",
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
#
# Check to see if user can do some action
#
# $ok = UserCan($user,$action)
#
sub UserCan {
    my ( $user, $action ) = @_;
    my @col;
    eval {
        @col =
          ExecSQL( $dbuser, $dbpasswd,
            "select count(*) from rwb_permissions where name=? and action=?",
            "COL", $user, $action );
    };
    if ($@) {
        return 0;
    }
    else {
        return $col[0] > 0;
    }
}

#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
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

## Create Checkboxes
sub CreateCheckboxes {
    my ( $formname, @list ) = @_;
    my $out;
    $out = "<form id=\"$formname\">\n";
    foreach my $cycle (@list) {
        $out .=
"<input type=\"checkbox\" name=\"cycles\" value=\"@{$cycle}\"> @{$cycle}<br>";
    }
    $out .= "</form>\n";
    return $out;
}

## send email to invited user
sub SendEmail {
    my ( $link, $email, $user ) = @_;
    my $body =
"Hello, $user sent you an invitation link to RWB Map. You may click the link below to create an account:\n$link";

    # Not finished: query user email
    my @existing_user_email = ();
    eval {
        ## bug-potential: not sure if query is correct
        @existing_user_email =
          ExecSQL( $dbuser, $dbpasswd,
            "select email from rwb_users where name=?",
            undef, $user );
    };
    open( MAIL, "| /usr/sbin/sendmail -t $email" );
    print MAIL "To: $email\n";
    print MAIL "From: $existing_user_email[0]\n";
    print MAIL "Content-Type: text/html\n";
    print MAIL "Subject: RWB Invitation\n";
    print MAIL $body;
    close MAIL;
}

## Confirm if the invite key is unique
### not finished
sub ConfirmUniqueInviteKey {
    my ($alpha_string) = @_;
    my $num_dupe = undef;
    eval {
        $num_dupe =
          ExecSQL( $dbuser, $dbpasswd,
            "select count(*) from invited_users where uuid=?",
            undef, $alpha_string );
    };
    if ( $num_dupe eq 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub registeredInviteKey {
    my ($alpha_string) = @_;
    my @account_created = undef;
    eval {
        @account_created =
          ExecSQL( $dbuser, $dbpasswd,
            "select registered from invited_users where uuid=?",
            undef, $alpha_string );
    };
    if ( $account_created[0][0] == 1 ) {
        return 1;
    }
    else {
        return 0;
    }
}

######################################################################
#
# Nothing important after this
#
######################################################################

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

