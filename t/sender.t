use strictures 1;
use Test::More;

use Object::Remote::Connector::Local;
use Object::Remote;
use Object::Remote::ModuleSender;

$ENV{PERL5LIB} = join(
  ':', ($ENV{PERL5LIB} ? $ENV{PERL5LIB} : ()), qw(lib)
);

my $connection = Object::Remote::Connector::Local->new->connect;

my $ms = Object::Remote::ModuleSender->new(
  dir_list => [ 't/lib' ]
);

my $ml = Object::Remote->new(
  connection => $connection,
  class => 'Object::Remote::ModuleLoader',
  args => { module_sender => $ms },
);

my $proxy = Object::Remote->new(
  connection => $connection,
  class => 'ORTestClass'
)->proxy;

isnt($$, $proxy->pid, 'Different pid on the other side');

is($proxy->counter, 0, 'Counter at 0');

is($proxy->increment, 1, 'Increment to 1');

is($proxy->counter, 1, 'Counter at 1');

done_testing;
