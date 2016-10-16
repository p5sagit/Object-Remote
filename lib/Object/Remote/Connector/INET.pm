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

=head1 NAME

Object::Remote::Connector::INET - A connector for INET sockets

=head1 DESCRIPTION

Used to create a connector that talks to an INET socket. Invoked by
L<Object::Remote/connect> if the connection spec is in C<host:port> format.

=head1 ARGUMENTS

Inherits arguments from L<Object::Remote::Role::Connector> and provides the
following:

=head2 socket_path

When invoked via L<Object::Remote/connect>, specified via the connection spec,
and not overridable.

The remote address to connect to. Expected to be understandable by
L<IO::Socket::INET> for its C<PeerAddr> argument.

=cut
