use strictures 1;
use Test::More;

$ENV{OBJECT_REMOTE_TEST_LOGGER} = 1;

use Object::Remote::Connector::Local; 
use Object::Remote::Connector::SSH; 

my $defaults = Object::Remote::Connector::Local->new;

my $normal = $defaults->final_perl_command;
my $ulimit = Object::Remote::Connector::Local->new(ulimit => "-v 536")->final_perl_command;
my $nice = Object::Remote::Connector::Local->new(nice => 834)->final_perl_command;
my $both = Object::Remote::Connector::Local->new(nice => 612, ulimit => "-v 913")->final_perl_command;
my $ssh = Object::Remote::Connector::SSH->new(nice => 494, ulimit => "-v 782", ssh_to => 'testhost')->final_perl_command;

is($defaults->timeout, 10, 'Default connection timeout value is correct');
is($defaults->watchdog_timeout, undef, 'Watchdog is not enabled by default');
is($defaults->nice, undef, 'Nice is not enabled by default');
is($defaults->ulimit, undef, 'Ulimit is not enabled by default');
is($defaults->stderr, undef, 'Child process STDERR is clone of parent process STDERR by default');

is_deeply($normal, ['bash', '-c', 'perl -'], 'Default Perl interpreter arguments correct');
is_deeply($ulimit, ['bash', '-c', 'ulimit -v 536 || exit 1; perl -'], 'Arguments for ulimit are correct');
is_deeply($nice, ['bash', '-c', 'nice -n 834 perl -'], 'Arguments for nice are correct');
is_deeply($both, ['bash', '-c', 'ulimit -v 913 || exit 1; nice -n 612 perl -'], 'Arguments for nice and ulimit are correct');
is_deeply($ssh, [qw(ssh -A testhost), "bash -c 'ulimit -v 782 || exit 1; nice -n 494 perl -'"], "Arguments using ssh are correct");

done_testing; 

