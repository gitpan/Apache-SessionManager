#
#    Apache::SessionManager.pm - mod_perl module to manage HTTP session
#
#    The Apache::SessionManager module is free software; you can redistribute it
#    and/or modify it under the same terms as Perl itself. 
#
#    See 'perldoc Apache::SessionManager' for documentation
#

package Apache::SessionManager;

require 5.005;
use strict;
use Apache::Constants qw(:common REDIRECT);
use Apache::Cookie ();
use Apache::URI ();
use Apache::Session::Flex;

use vars qw($VERSION);
$VERSION = '0.03';

# Translation URI handler (embeds simple management for session tracking via URI)
sub handler {
	my $r = shift;
	my (%session_config,%session,$session_id,%cookie_options);

	return DECLINED unless $r->is_initial_req;
			
	my $debug_prefix = "SessionManager ($$):";
	$session_config{'SessionManagerDebug'} = $r->dir_config("SessionManagerDebug") || 0;

	print STDERR "$debug_prefix ---START REQUEST: " .  $r->uri . " ---\n" if $session_config{'SessionManagerDebug'} > 0;
				
	# Get and remove session ID from URI
	if ( $r->dir_config("SessionManagerURITracking") eq 'On' ) {
		print STDERR "$debug_prefix start URI " . $r->uri . "\n" if $session_config{'SessionManagerDebug'} > 0;
	
		# retrieve session ID from URL (or HTTP 'Referer:' header)
		my (undef, $uri_session_id, $rest) = split /\/+/, $r->uri, 3;

		if ( $uri_session_id =~ /^[0-9a-h]+$/ ) {
			$session_id = $uri_session_id;
			# Remove the session from the URI
			$r->uri("/$rest");
			print STDERR "$debug_prefix end URI " . $r->uri . "\n" if $session_config{'SessionManagerDebug'} > 0;			
		}
	}
	
	# declines each request if session manager is off
	return DECLINED unless ( $r->dir_config("SessionManagerTracking") eq 'On' );

	# Set exclusion extension(s)
	$session_config{'SessionManagerItemExclude'} = $r->dir_config("SessionManagerItemExclude") || '(\.gif|\.jpe?g|\.png|\.mpe?g|\.css|\.js|\.txt|\.mp3|\.wav|\.swf|\.avi|\.au|\.ra?m)$';

	# returns if resource type is to exlcude
	return DECLINED if ( $r->uri =~ /$session_config{'SessionManagerItemExclude'}/i );

	$session_config{'SessionManagerStore'} = $r->dir_config("SessionManagerStore") || 'File';
	$session_config{'SessionManagerLock'} = $r->dir_config("SessionManagerLock") || 'Null';
	$session_config{'SessionManagerGenerate'} = $r->dir_config("SessionManagerGenerate") || 'MD5';
	$session_config{'SessionManagerSerialize'} = $r->dir_config("SessionManagerSerialize") || 'Storable';
	$session_config{'SessionManagerExpire'} = $r->dir_config("SessionManagerExpire") || 3600;
	$session_config{'SessionManagerInactivity'} = $r->dir_config("SessionManagerInactivity");
	$session_config{'SessionManagerName'} = $r->dir_config("SessionManagerName") || 'PERLSESSIONID';

	if ( $session_config{'SessionManagerDebug'} >= 3 ) {
		print STDERR "$debug_prefix configuration settings\n";
		foreach (sort keys %session_config)	{
		   print STDERR "\t$_ = $session_config{$_}\n";
		}
	}
	
	# Get session ID from cookie
	unless ( $r->dir_config("SessionManagerURITracking") eq 'On' ) {
		my %cookies = Apache::Cookie->fetch; 
		$session_id = $cookies{$session_config{'SessionManagerName'}}->value if defined $cookies{$session_config{'SessionManagerName'}};
	}

	# Prepare Apache::Session::Flex options parameters call
	my %apache_session_flex_options = (
		Store     => $session_config{'SessionManagerStore'},
		Lock      => $session_config{'SessionManagerLock'},
		Generate  => $session_config{'SessionManagerGenerate'},
		Serialize => $session_config{'SessionManagerSerialize'}
	); 

	# Load session data store specific parameters
	foreach my $arg ( split(/\s*,\s*/,$r->dir_config('SessionManagerStoreArgs')) ) {
		my ($key,$value) = split(/\s*=>\s*/,$arg);
		$apache_session_flex_options{$key} = $value;
	}

	if ( $session_config{'SessionManagerDebug'} >= 5 ) {
		print STDERR "$debug_prefix Apache::Session::Flex options\n";
		foreach (sort keys %apache_session_flex_options)	{
		   print STDERR "\t$_ = $apache_session_flex_options{$_}\n";
		}
	}

	# Experimental code (support for mod_backhand)
	$session_id = substr($session_id,8) if ( $r->dir_config('SessionManagerEnableModBackhand') eq 'On' );
	 
	# Try to retrieve session object from session ID
	my $res = _tieSession(\%session, $session_id, \%apache_session_flex_options,$session_config{'SessionManagerDebug'});

	# Session ID not found or invalid session: a new object session will be create
	if ($res) {
		my $res = _tieSession(\%session, undef, \%apache_session_flex_options,$session_config{'SessionManagerDebug'});
		$session_id = undef;
	}

	# for new or invalid session's ID put session start time in special session key '_session_start'
	$session{'_session_start'} = time if ! defined $session{'_session_start'};

	# session's expiration date check only for existing sessions
	if ( $session_id ) {
		print STDERR "$debug_prefix  checking TTL session, ID = $session_id ($session{'_session_timestamp'})\n" if $session_config{'SessionManagerDebug'} > 0;
		# Session TTL expired: a new object session is create
		if ( ( $session_config{'SessionManagerInactivity'} && 
		       (time - $session{'_session_timestamp'}) > $session_config{'SessionManagerInactivity'} ) 
			  || 
			  ( $session_config{'SessionManagerExpire'} && 
			    (time - $session{'_session_start'}) > $session_config{'SessionManagerExpire'} ) ) {
			print STDERR "$debug_prefix session to delete\n" if $session_config{'SessionManagerDebug'} > 0;
			tied(%session)->delete;
			
			my $res = _tieSession(\%session, undef, \%apache_session_flex_options,$session_config{'SessionManagerDebug'});

			$session_id = undef;
			$session{'_session_start'} = time;
		}
	}

	# Update '_session_timpestamp' session value only if required
	$session{'_session_timestamp'} = time if $session_config{'SessionManagerInactivity'};
	
	# store object session reference in pnotes to share it over other handlers
	$r->pnotes('SESSION_MANAGER_HANDLE' => \%session );

	# set 'SESSION_MANAGER_SID' env variable to session ID to make it available to CGI/SSI scripts
   $r->subprocess_env(SESSION_MANAGER_SID => $session{_session_id}) if ($r->dir_config("SessionManagerSetEnv") eq 'On');

	$r->register_cleanup(\&cleanup);

	# Foreach new session we:
	unless ( $session_id ) {
		my $session_id = $session{_session_id};
		
		if ( $r->dir_config('SessionManagerEnableModBackhand') eq 'On' ) {
			my $hex_addr = join "", map { sprintf "%lx", $_ } unpack('C4', gethostbyname($r->get_server_name));
			$session_id = $hex_addr . $session_id;
		}

		# redirect to embedded session ID URI...
		if ( $r->dir_config("SessionManagerURITracking") eq 'On' ) {
			print STDERR "$debug_prefix URI redirect...\n" if $session_config{'SessionManagerDebug'} > 0;
			_redirect($r,$session_id);
			return REDIRECT;
		}
		# ...or send cookie to browser
		else {
			print STDERR "$debug_prefix sending cookie...\n" if $session_config{'SessionManagerDebug'} > 0;
			# Load cookie specific parameters
			foreach my $arg ( split(/\s*,\s*/,$r->dir_config('SessionManagerCookieArgs')) ) {
				my ($key,$value) = split(/\s*=>\s*/,$arg);
				$cookie_options{lc($key)} = $value if $key =~ /^(expires|domain|path|secure)$/i;
			}
			if ( $session_config{'SessionManagerDebug'} >= 5 ) {
				print STDERR "$debug_prefix Cookie options\n";
				foreach (sort keys %cookie_options)	{
				   print STDERR "\t$_ = $cookie_options{$_}\n";
				}
			}
			my $cookie = Apache::Cookie->new($r,
				name => $session_config{'SessionManagerName'},
				value => $session_id,
				%cookie_options
			  );
			$cookie->bake;
		}
	}
	
	print STDERR "$debug_prefix ---END REQUEST---\n" if $session_config{'SessionManagerDebug'} > 0;
		
	return DECLINED;
}

sub cleanup {
	my $r = shift;
	return DECLINED unless ( $r->dir_config("SessionManagerTracking") eq 'On' );
	my $session = ref $r->pnotes('SESSION_MANAGER_HANDLE') ? $r->pnotes('SESSION_MANAGER_HANDLE') : {};
	untie %{$session};
	return DECLINED;
}

sub get_session {
	my $r = shift;
	return ($r->pnotes('SESSION_MANAGER_HANDLE')) ? $r->pnotes('SESSION_MANAGER_HANDLE') : ();
}

sub destroy_session {
	my $r = shift;
	my $session = (ref $r->pnotes('SESSION_MANAGER_HANDLE')) ? $r->pnotes('SESSION_MANAGER_HANDLE') : {};
	tied(%{$session})->delete;
}

sub _tieSession {
	my ($session_ref,$id,$options,$debug) = @_;
	eval {
		tie %{$session_ref}, 'Apache::Session::Flex', $id, $options;
	};
	print STDERR "Tied session ID = $$session_ref{_session_id}\n$@" if $debug >= 3 ;
	return $@ if $@;
}

# _redirect function adapted from original redirect sub wrote by Greg Cope
sub _redirect {
	my $r = shift;
	my $session_id = shift || '';
	my ($args, $host, $rest, $redirect);
	($host, $rest) = split '/', $r->uri, 2;
	$args = $r->args || '';
	$args = '?' . $args if $args;
	$r->content_type('text/html');
 
	# "suggest by Gerald Richter / Matt Sergeant to add scheme://hostname:port to redirect" (Greg's note)
	my $uri = Apache::URI->parse($r);
 
	# hostinfo give port if necessary - otherwise not
	my $hostinfo = $uri->hostinfo;
	my $scheme =  $uri->scheme . '://';
	$session_id .= '/' if ($session_id);
	$redirect = $scheme . $hostinfo . '/'. $session_id . $rest . $args;
	# if no slash and it's a dir add a slash
	if ($redirect !~ m#/$# && -d $r->lookup_uri($redirect)->filename) {
		$redirect .= '/';
	}
	$r->header_out(Location => $redirect);
} 

1;

=pod 

=head1 NAME

Apache::SessionManager - mod_perl extension to manage sessions 
over HTTP requests

=head1 SYNOPSIS

In httpd.conf:

   PerlModule Apache::SessionManager
   PerlTransHandler Apache::SessionManager
	  
   <Location /my-app-with-session>
      SetHandler perl-script
      PerlHandler Apache::MyModule
      PerlSetVar SessionManagerTracking On
      PerlSetVar SessionManagerExpire 3600
      PerlSetVar SessionManagerInactivity 900
      PerlSetVar SessionManagerStore File
      PerlSetVar SessionManagerStoreArgs "Directory => /tmp/apache_sessions"
   </Location>  

   <Location /my-app-without-sessions>
      PerlSetVar SessionManagerTracking Off
   </Location>

=head1 DESCRIPTION

Apache::SessionManager is a mod_perl module that helps 
session management of a web application. This simple module is a 
wrapper around Apache::Session persistence framework for session data.
It creates a session object and makes it available to all other handlers 
transparenlty by putting it in pnotes. In a mod_perl handlers you can retrieve 
the session object directly from pnotes with predefined key 
'SESSION_MANAGER_HANDLE':

   my $session = $r->pnotes('SESSION_MANAGER_HANDLE') ? $r->pnotes('SESSION_MANAGER_HANDLE') : ();

In a CGI Apache::Registry script:

   my $r = Apache->request;
   my $session = $r->pnotes('SESSION_MANAGER_HANDLE') ? $r->pnotes('SESSION_MANAGER_HANDLE') : (); 

then it is possible to set a value in current session with:

   $$session{'key'} = $value;

or read value session with:

   print "$$session{'key'}";

The following functions also are provided (but not yet exported) by this module: 

=over 4

=item Apache::SessionManager::get_session(Apache->request)

Return an hash reference to current session object.

=item Apache::SessionManager::destroy_session(Apache->request)

Destroy the current session object.

=back

For instance:

   package Apache::MyModule;
   use strict;
   use Apache::Constants qw(:common);

   sub handler {
      my $r = shift;

      # retrieve session
      my $session = Apache::SessionManager::get_session($r);

      # set a value in current session
      $$session{'key'} = "some value";
 
      # read value session
      print "$$session{'key'}";

      # destroy session explicitly
      Apache::SessionManager::destroy_session($r);
      
      ...
 
      return OK;
   } 

=head1 INSTALLATION

In order to install and use this package you will need Perl version
5.005 or better.

Prerequisites:

=over 4

=item * mod_perl (of course) with the appropriate call-back hooks (PERL_TRANS=1)

=item * Apache::Request >= 0.33 (libapreq) is required

=item * Apache::Session >= 0.53 is required

=back 

Installation as usual:

   % perl Makefile.PL
   % make
   % make test
   % su
     Password: *******
   % make install

=head1 CONFIGURATION

To enable session tracking with this module you should modify 
a configuration in B<httpd.conf> by adding the following lines:

   PerlModule Apache::SessionManager
   PerlTransHandler Apache::SessionManager
   PerlSetVar SessionManagerTracking On

This will activate the session manager over each request.
It is posibible to activate this module by location or directory
only:

   <Location /my-app-dir>
      PerlSetVar SessionManagerTracking On
   </Location>

Also, it is possible to deactivate session management per 
directory or per location explicitly:

   <Location /my-app-dir-without>
      PerlSetVar SessionManagerTracking Off
   </Location>

=head1 DIRECTIVES

You can control the behaviour of this module by configuring
the following variables with C<PerlSetVar> directive 
in the B<httpd.conf>.

=over 4

=item C<SessionManagerTracking> On|Off

This single directive enables session traking

   PerlSetVar SessionManagerTracking On

It can be placed in server config, <VirtualHost>, <Directory>, 
<Location>, <File> and .htaccess context.
The default value is C<Off>.

=item C<SessionManagerURITracking> On|Off

This single directive enables session URI traking

   PerlSetVar SessionManagerURITracking On

where the session ID is embedded in the URI.
This is a possible cookieless solution to track
session ID between browser and server.
Please see C<URI TRACKING NOTES> section below for more details.
The default value is C<Off>.

=item C<SessionManagerExpire> number

This single directive defines global sessions expiration time
(in seconds).

   PerlSetVar SessionManagerExpire 900

The default value is C<3600> seconds.
The module put the user start session time in a special session key 
'_session_start'.

=item C<SessionManagerInactivity> number

This single directive defines user inactivity sessions expiration time
(in seconds).

   PerlSetVar SessionManagerInactivity 900

If not specified no user inactivity expiration policies are applied.
The module put the user timestamp in a special session key 
'_session_timestamp'.

=item C<SessionManagerName> string

This single directive defines session cookie name

   PerlSetVar SessionManagerName PSESSID

The default value is C<PERLSESSIONID>

=item C<SessionManagerCookieArgs>

With this directive you can provide optional arguments 
for cookie attributes setting. The arguments are passed as 
comma-separated list of name/value pairs. The only attributes 
accepted are:

=over 4

=item * Domain

Set the domain for the cookie.

=item * Path

Set the path for the cookie.

=item * Secure

Set the secure flag for the cookie. 

=item * Expire

Set expire time for the cookie.

=back

For instance:

   PerlSetVar SessionManagerCookieArgs "Path   => /some-path, \
                                        Domain => .yourdomain.com, \
                                        Secure => 1"

Please see the documentation for C<Apache::Cookie> or C<CGI::Cookie> in order
to see more cookie arguments details.

=item C<SessionManagerStore> datastore

This single directive sets the session datastore 
used by Apache::Session framework

   PerlSetVar SessionManagerStore File

The following datastore plugins are available with 
Apache::Session distribution:

=over 4

=item * File

Sessions are stored in file system

=item * MySQL

Sessions are stored in MySQL database

=item * Postgres

Sessions are stored in Postgres database

=item * Sybase

Sessions are stored in Sybase database

=item * Oracle

Sessions are stored in Oracle database

=item * DB_File

Sessions are stored in DB files

=back

In addition to datastore plugins shipped with Apache::Session,
you can pass the modules you want to use as arguments to the
store constructor. The Apache::Session::Whatever part is
appended for you: you should not supply it.
If you wish to use a module of your own making, you should 
make sure that it is available under the Apache::Session 
package namespace.
For example:

   PerlSetVar SessionManagerStore SharedMem

in order to use Apache::Session::SharedMem to store
sessions in RAM (but you must install Apache::Session::SharedMem 
before!)

The default value is C<File>.

=item C<SessionManagerLock> Null|MySQL|Semaphore|File

This single directive set lock manager for Apache::Session::Flex.
The default value is C<Null>.

=item C<SessionManagerGenerate> MD5|ModUniqueId|ModUsertrack

This single directive set session ID generator for Apache::Session::Flex.
The default value is C<MD5>.

=item C<SessionManagerSerialize> Storable|Base64|UUEncode

This single directive set serializer for Apache::Session::Flex.
The default value is C<Storable>.

=item C<SessionManagerStoreArgs>

With this directive you must provide whatever arguments 
are expected by the backing store and lock manager 
that you've chosen. The arguments are passed as comma-separated 
list of name/value pairs.

For instance if you use File for your datastore, you
need to pass store and lock directories:

   PerlSetVar SessionManagerStoreArgs "Directory     => /tmp/apache_sessions, \
                                       LockDirectory => /tmp/apache_sessions/lock"

If you use MySQL for your datastore, you need to pass database 
connection informations:

   PerlSetVar SessionManagerStoreArgs "DataSource => dbi:mysql:sessions, \
                                       UserName   => user, \
                                       Password   => password" 

Please see the documentation for store/lock modules in order
to pass right arguments.

=item C<SessionManagerItemExclude> string|regex

This single directive defines the exclusion string.
For example:

   PerlSetVar SessionManagerItemExclude exclude_string

All the HTTP requests containing the 'exclude_string' string
will be declined. Also is possible to use regex:

   PerlSetVar SessionManagerItemExclude "\.m.*$"

and all the request (URI) ending by ".mpeg", ".mpg" or ".mp3" will be declined.

The default value is:

C<(\.gif|\.jpe?g|\.png|\.mpe?g|\.css|\.js|\.txt|\.mp3|\.wav|\.swf|\.avi|\.au|\.ra?m)$>

=item C<SessionManagerSetEnv> On|Off

This single directive set the C<SESSION_MANAGER_SID> environment 
variable with the current (valid) session ID:

   PerlSetVar SessionManagerSetEnv On

It makes session ID available to CGI scripts for use in absolute
links or redirects. The default value is C<Off>.

=item C<SessionManagerDebug> level

This single directive set debug level.

   PerlSetVar SessionManagerDebug 3

If greather than zero, debug informations will be print to STDERR.
The default value is C<0> (no debug information will be print).

=item C<SessionManagerEnableModBackhand> On|Off

This single directive enable 'experimental' mod_backhand sticky session
load balancing support.
Someone asked me this feature, so I've added it.

   PerlSetVar SessionManagerEnableModBackhand On

A few words on mod_backhand. mod_backhand is a load balancing Apache module.
mod_backhand can attempt to find a cookie in order to hex decodes the first 8 
bytes of its content into an IPv4 style IP address.
It will attempt to find this IP address in the list of candidates
and if it is found it will make the server in question the only remaining
candidate. This can be used to implement sticky user sessions -- where a 
given user will always be delivered to the same server once a session 
has been established.
Simply turning on this directive, you add hex IP address in front to session_id.
See mod_backhand docs for more details (http://www.backhand.org/mod_backhand).

The default value is C<Off>.

=back

=head1 URI TRACKING NOTES

There are some considerations and issues in order to
use the session ID embedded in the URI.
In fact, this is a possible cookieless solution to track
session ID between browser and server.

If you enable session ID URI tracking you must
place all the PerlSetVar directives you need
in server config context (that is outside of <Directory> or 
<Location> sections) otherwise the handler will not work for 
these requests. The reason of this is that the URI will be rewrite
with session ID on the left and all <Location> that you've defined 
will match no longer.

Alternatively it is possible to use <LocationMatch>
section. For instance:

   PerlModule Apache::SessionManager
   PerlTransHandler Apache::SessionManager
		
   <LocationMatch "^/([0-9a-h]+/)?my-app-dir">
      SetHandler perl-script
      PerlHandler MyModule
      PerlSetVar SessionManagerTracking On
      PerlSetVar SessionManagerURITracking On
      PerlSetVar SessionManagerStore File
      PerlSetVar SessionManagerStoreArgs "Directory => /tmp/apache_sessions"
   </LocationMatch>

to match also URI with embedded session ID.

Another issue is if you use a front-end/middle-end 
architecture with a reverse proxy front-end server
in front (for static content) and a mod_perl enabled
server in middle tier to serve dynamic contents.
If you use Apache as reverse proxy it became
impossible to set the ProxyPass directive either because
it can be palced only in server config and/or
<VirtualHost> context, either because it isn't
support for regex to match session ID embedded in the URI.

In this case, you can use the proxy support available
via the C<mod_rewrite> Apache module by putting 
in front-end server's httpd.conf:

   ProxyPass /my-app-dir http://middle-end.server.com:9000/my-app-dir
   ProxyPassReverse / http://middle-end.server.com:9000/

   RewriteEngine On
   RewriteRule (^/([0-9a-h]+/)?my-app-dir.*) http://middle-end.server.com:9000$1 [P,L]

Take careful to make all links to static content as non relative
link (use "http://myhost.com/images/foo.gif" or "/images/foo.gif")
or the rewrite engine will proxy these requests to mod_perl server.

=head1 TODO

=over 4

=item * 

Add an OO interface by subclassing Apache request object directly

=item * 

Add the possibility of auto-switch session ID tracking 
from cookie to URI in cookieless situation.
The code from Greg Cope session manager implementation could be integrated.

=item * 

Add the query string param support (other than cookie and URI) to track session ID
between browser and server.

=item * 

Include into the distro the session cleanup script (the scripts I use for 
cleanup actually)

=item * 

Embed the cleanup policies not in a extern scripts but in a
register_cleanup method

=item * 

Update test suite to run correclty under Win32 platform

=item * 

Test, test ,test

=back

=head1 AUTHORS

Enrico Sorcinelli <enrico@sorcinelli.it>

=head1 THANKS

A particular thanks to Greg Cope <gjjc@rubberplant.freeserve.co.uk> 
for freeing Apache::SessionManager namespace from his RFC (October 2000).
His SessionManager project can be found at 
http://sourceforge.net/projects/sessionmanager

=head1 BUGS 

This library has been tested by the author with Perl versions 5.005,
5.6.0 and 5.6.1 on different platforms: Linux 2.2 and 2.4, Solaris 2.6
and 2.7 and Windows 98.

Send bug reports and comments to: enrico@sorcinelli.it
In each report please include the version module, the Perl version,
the Apache, the mod_perl version and your SO. If the problem is 
browser dependent please include also browser name and
version.
Patches are welcome and I'll update the module if any problems 
will be found.

=head1 SEE ALSO

L<Apache::Session>, L<Apache::Session::Flex>, L<Apache::Request>, 
L<Apache::Cookie>, L<Apache>, L<perl(1)>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2001,2002 Enrico Sorcinelli. All rights reserved.
This program is free software; you can redistribute it 
and/or modify it under the same terms as Perl itself. 

=cut

__END__
