use IO::Prompter; # dies, utterly, if loaded after strictures, no idea why
use strictures 1;
use Test::More;
use lib 'xt/lib';

use Object::Remote;
use Object::Remote::Connector::LocalSudo;


my $user = $ENV{TEST_SUDOUSER}
    or plan skip_all => q{Requires TEST_SUDOUSER to be set};

my $pw;

my $connector = Object::Remote::Connector::LocalSudo->new(
  password_callback => sub {
    $pw ||= prompt 'Sudo password', -echo => '*';
  }
);

my $remote = TestFindUser->new::on($connector->connect($user));
my $remote_user = $remote->user;
like $remote_user, qr/^\d+$/, 'returned an int';
isnt $remote_user, $<, 'ran as different user';

$remote->send_err;

done_testing;
