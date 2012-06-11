use strictures 1;
use Test::More;
use Sys::Hostname qw(hostname);

use Object::Remote;

$ENV{PERL5LIB} = join(
  ':', ($ENV{PERL5LIB} ? $ENV{PERL5LIB} : ()), qw(lib t/lib)
);

my $connection = Object::Remote->connect('-');

#$Object::Remote::Connection::DEBUG = 1;

my $remote = ORTestClass->new::on($connection);

isnt($$, $remote->pid, 'Different pid on the other side');

is($remote->counter, 0, 'Counter at 0');

is($remote->increment, 1, 'Increment to 1');

is($remote->counter, 1, 'Counter at 1');

my $x = 0;

is($remote->call_callback(27, sub { $x++ }), 27, "Callback ok");

is($x, 1, "Callback called callback");

is(
  $connection->remote_sub('Sys::Hostname::hostname')->(),
  hostname(),
  'Remote sub call ok'
);

done_testing;
