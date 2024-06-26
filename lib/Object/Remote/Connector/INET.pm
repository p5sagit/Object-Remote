package Object::Remote::Connector::INET;

use IO::Socket::INET;
use Moo;

with 'Object::Remote::Role::Connector';

has socket_path => (is => 'ro', required => 1);

sub _open2_for {
  my ($self) = @_;
  my $path = $self->socket_path;
  my $sock = IO::Socket::INET->new($path)
    or die "Couldn't open socket ${path}: $!";
  ($sock, $sock, undef);
}

no warnings 'once';

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    if (defined and !ref and /^.+:\d+$/) {
      my $socket = shift(@_);
      return __PACKAGE__->new(@_, socket_path => $socket);
    }
  }
  return;
};

1;
