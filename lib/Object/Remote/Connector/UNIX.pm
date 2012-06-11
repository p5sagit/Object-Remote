package Object::Remote::Connector::UNIX;

use IO::Socket::UNIX;
use Moo;

with 'Object::Remote::Role::Connector';

sub _open2_for {
  my ($self,$path) = @_;
  my $sock = IO::Socket::UNIX->new($path)
    or die "Couldn't open socket ${path}: $!";
  ($sock, $sock, undef);
}

no warnings 'once';

push @Object::Remote::Connection::Guess, sub { 
  for ($_[0]) {
    if (defined and !ref and /^(?:\.\/|\/)/) {
      return __PACKAGE__->new->connect($_[0]);
    }
  }
  return;
};

1;
