use strictures 1;
use Test::More;

require 't/logsetup.pl';

use Object::Remote;
use Object::Remote::Connector::Local;

my $connector = Object::Remote::Connector::Local->new(
  timeout => { after => 0.1 },
  perl_command => [ 'perl', '-e', 'sleep 3' ],
);

ok(!eval { $connector->connect; 1 }, 'Connection failed');

like($@, qr{timed out}, 'Connection failed with time out');

done_testing;
