

my $necessary_modules = {
	'Apache' => 'The Apache Perl API',
	'Apache::Session' => 'A persistence framework for session data'
};

my $optional_modules = {
	'Apache::Request' => 'Apache API to manage HTTP cookies'
};

print "Checking for the REQUIRED modules...\n";
my($errors, $warnings);
for(sort keys %$necessary_modules) {
	eval 'use ' . $_ ;
	my $module_display = $_;
	$module_display =~ s/( [\d\.]+)$/ \>\=$1/isg;
	if($@) {
		$errors++;
		print " !!! you need module: $module_display\n";
		print "     CAUSE: $necessary_modules->{$_}\n";
	}
	else {
		print " --> found $module_display\n";
	}
}

print "\nChecking for the OPTIONAL modules...\n";
for(sort keys %$optional_modules) {
	my $data = $optional_modules->{$_};
	my $message = ref($data) ? $data->{message} : $data;

	# if there is a test for this module run it and if returns false
	# skip this module's message, first so UNIX users don't see 
	# message about, ad ex., Win32::OLE
	if(ref($data) && $data->{test} && ! eval($data->{test})) {
		next;
	}

	{
		local $SIG{__DIE__} = sub { die(@_); };
		eval 'use ' . $_ ;
		my $module_display = $_;
		$module_display =~ s/( [\d\.]+)$/ \>\=$1/isg;
		if($@) {
			$warnings++;
			print " ??? you may need module: $module_display\n";
			print "     CAUSE: $optional_modules->{$_}\n";
#			print "   ERROR: $@\n";
		} 
		else {
			print " --> found $module_display\n";
		}
	}
}

my $CPAN = <<CPAN;

-=-= CPAN HELP =-=-

There are many modules that have to be installed in order
to begin using Apache::SessionManager. The easiest way to install
modules is with CPAN.pm.  To use its command line shell,
execute the following: 

% perl -MCPAN -eshell

Then to install any required modules, like Apache::Session:

  cpan> install Apache::Session

and cpan will do this for you.  For more
information, please view the CPAN docs with:

% perldoc CPAN

-=-= CPAN HELP =-=-

CPAN

if($errors) {
	print "\nExiting now because of errors!\n";
	print $CPAN,"\n";
	exit;
} 
elsif($warnings) {
	print $CPAN;
} 

print "Required modules founded!\n";

# Apache / mod_perl test
eval { require Apache::test };
if ( !$@ ) {
	my %params = Apache::test->get_test_params();
	Apache::test->write_httpd_conf( %params, include => join('', <DATA>) );
	*MY::test = sub { Apache::test->MM_test(%params) }; 
}  

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	'NAME'         => 'Apache::SessionManager',
	'AUTHOR'       => 'Enrico Sorcinelli <enrico@sorcinelli.it>',
	'ABSTRACT'     => 'Apache mod_perl module to manage HTTP sessions',
	'VERSION_FROM'	=> 'SessionManager.pm', # finds $VERSION
	'PREREQ_PM'		=> {
                      "mod_perl"        => "1.24",
                      "Apache::Session" => "1.54",
                      #"Apache::Request" => "0.33",
                     }, # e.g., Module::Name => 1.1
	'clean'        => {FILES => 't/httpd.conf t/error_log t/httpd'},							
);

__DATA__
# Apache::SessionManager configuration section
PerlModule Apache::SessionManager
PerlTransHandler Apache::SessionManager
PerlSetVar SessionManagerTracking On
PerlSetVar SessionManagerDebug 5

# These documents require cookies session
<Location /session>
	SetHandler perl-script
	PerlHandler PrintEnv
	PerlSetVar SessionManagerStore File
	PerlSetVar SessionManagerLock File
	PerlSetVar SessionManagerCookieArgs "Path => /session, Secure => 0, Extras => some_value"
	PerlSetVar SessionManagerStoreArgs "Directory => /tmp"
	PerlSetVar SessionManagerSetEnv On
</Location>

# These documents require cookies session w/authentication
<Location /session-auth>
	SetHandler perl-script
	PerlHandler PrintEnv
	PerlSetVar SessionManagerStore File
	PerlSetVar SessionManagerLock File
	PerlSetVar SessionManagerCookieArgs "Path => /session-auth, Secure => 0"
	PerlSetVar SessionManagerStoreArgs "Directory => /tmp"
	PerlSetVar SessionManagerSetEnv On

	AuthName "Reserved Club"
	AuthType Basic
	require valid-user
	PerlAuthenHandler MyAuth
	PerlSetVar MyAuthLogin /protected/login.html 
</Location>

# These documents URI tracking session
<LocationMatch "^/([0-9a-h]+/)?uri-session">
   SetHandler perl-script
   PerlHandler PrintEnv
	PerlSetVar SessionManagerURITracking On
	PerlSetVar SessionManagerStore File
	PerlSetVar SessionManagerLock File
	PerlSetVar SessionManagerStoreArgs "Directory => /tmp"
	PerlSetVar SessionManagerSetEnv On
</LocationMatch>

# These documents require cookies session + mod_baskhand cookie load-balancing
<Location /session-bh>
	SetHandler perl-script
	PerlHandler PrintEnv
	PerlSetVar SessionManagerStore File
	PerlSetVar SessionManagerLock File
	PerlSetVar SessionManagerCookieArgs "Path => /session-bh"
	PerlSetVar SessionManagerStoreArgs "Directory => /tmp"
	PerlSetVar SessionManagerEnableModBackhand On
	PerlSetVar SessionManagerSetEnv On
</Location>

# These documents don't require cookies session
<Location /no-session>
   SetHandler perl-script
   PerlHandler PrintEnv
   PerlSetVar SessionManagerTracking Off
</Location>

<Location /perl-status>
   SetHandler perl-script
   PerlHandler Apache::Status
</Location>
