package Object::Remote::Connector::UNIX;

use IO::Socket::UNIX;
use Moo;

with 'Object::Remote::Role::Connector';

has socket_path => (is => 'ro', required => 1);

sub _open2_for {
  my ($self) = @_;
  my $path = $self->socket_path;
  my $sock = IO::Socket::UNIX->new($path)
    or die "Couldn't open socket ${path}: $!";
  ($sock, $sock, undef);
}

no warnings 'once';

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    if (defined and !ref and /^(?:\.\/|\/)/) {
      my $socket = shift(@_);
      return __PACKAGE__->new(@_, socket_path => $socket);
    }
  }
  return;
};

1;

=head1 NAME

Object::Remote::Connector::UNIX - A connector for UNIX sockets

=head1 ARGUMENTS

Inherits arguments from L<Object::Remote::Role::Connector> and provides the
following:

=head2 socket_path

=cut
