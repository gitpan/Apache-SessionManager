package PrintEnv;

require 5.005;
use strict;
use Apache::Constants qw(:common);

use vars qw($VERSION);
$VERSION = '0.1';

sub handler {
	my $r = shift;
	my $session = Apache::SessionManager::get_session($r);
	my $str;

	# Main output
   $str = <<EOM;
<HTML>
<HEAD><TITLE>mod_perl Apache::SessionManager test module</TITLE></HEAD>
<BODY BGCOLOR="#FFFFFF">
<CENTER><H1>mod_perl Apache::SessionManager test module</H1>
<H3>Session start at $$session{'_session_start'}</H3></CENTER>
<H2>Environment variables:</H2>
EOM
	foreach (sort keys %{$r->subprocess_env}) {
		$str .= "<B>$_</B>=" . $r->subprocess_env->{$_} . "<BR>\n";
	}

	$str .= "<H2>HTTP request headers:</H2>";
	foreach (sort keys %{$r->headers_in()}) {
		$str .= "<B>$_</B>=" . $r->headers_in->{$_} . "<BR>\n";
	}
	$str .= "</BODY>\n</HTML>";
	
	# set session value
	$$session{'random'} = rand;
		
   # Output code to client
   $r->content_type('text/html'); 
   $r->send_http_header;
   $r->print($str);
   return OK;
}
