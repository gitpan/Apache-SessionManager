package PrintEnv;

require 5.005;
use strict;
use Apache::Constants qw(:common);
use Data::Dumper;

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
<CENTER><H1>mod_perl Apache::SessionManager test module</H1></CENTER>
EOM

	$str .= '<PRE>' . Data::Dumper::Dumper($session) . '</PRE>';
#	$str .= HashVariables($session,'<H2>Session Dump</H2>');
	$str .= HashVariables(\%INC,'<H2>%INC</H2>');
	$str .= HashVariables($r->subprocess_env,'<H2>Environment variables</H2>');
	$str .= HashVariables({$r->headers_in()},'<H2>HTTP request headers</H2>');
	$str .= "</BODY>\n</HTML>";
	
	# set session value
	$$session{rand()} = rand;

   # Output code to client
   $r->content_type('text/html'); 
   $r->send_http_header;
   $r->print($str);
   return OK;
}

sub HashVariables {
	my($hash,$topic) = @_;
   my $str = $topic;
   foreach(sort keys %$hash) {
      $str .= "<B>$_</B> = $$hash{$_}<BR>\n";
   }
   return $str;
}  
