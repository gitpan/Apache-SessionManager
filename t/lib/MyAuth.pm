package MyAuth;
use Apache::Constants qw(:common REDIRECT);
use Apache::SessionManager;
use strict;

sub handler {
   my $r = shift;
   my $session = Apache::SessionManager::get_session($r);

   # Login ok: user is already logged or login form is requested
   if ( $session->{'logged'} == 1 || $r->uri eq $r->dir_config('MyAuthLogin') ) { 
      return OK;
   }
   # user not logged in or session expired

   # store in session the destination url if not set
   $session->{'redirect'} ||= $r->uri . ( ( $r->args ) ? ('?' . $r->args) : '' );

   # verify credenitals
   unless ( verifiy_cred( ($r->args) ) ) {
      # Log error
      $r->log_error('MyAuth: access to ' . $r->uri . ' failed for ' . $r->get_remote_host);
      # Redirect to login page
      $r->custom_response(FORBIDDEN, $r->dir_config('MyAuthLogin'));
      return FORBIDDEN;
   }
   $session->{'logged'} = 1;
   # Redirect to original protected resource
   $r->content_type('text/html'); 
   $r->header_out( Location => $session->{'redirect'} );
   return REDIRECT;     
}

sub verifiy_cred {
   my %cred = @_;
   # Check correct username and password
   return 1 if ( $cred{'username'} eq 'foo' && $cred{'password'} eq 'baz' );
   return 0;
}

1;
