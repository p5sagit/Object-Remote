package Object::Remote::Connector::SSH;

use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use String::ShellQuote;
use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

has ssh_to => (is => 'ro', required => 1);

has ssh_perl_command => (is => 'lazy');

has ssh_options => (is => 'ro', default => sub { [ '-A' ] });

has ssh_command => (is => 'ro', default => sub { 'ssh' });

sub _build_ssh_perl_command {
  my ($self) = @_;
  my $perl_command = $self->perl_command;

  return [
    do { my $c = $self->ssh_command; ref($c) ? @$c : $c },
    @{$self->ssh_options}, $self->ssh_to,
    shell_quote(@$perl_command),
  ];
}

sub final_perl_command { shift->ssh_perl_command }

no warnings 'once';

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    # 0-9 a-z _ - first char, those or . subsequent - hostnamish
    if (defined and !ref and /^(?:.*?\@)?[\w\-][\w\-\.]/) {
      my $host = shift(@_);
      return __PACKAGE__->new(@_, ssh_to => $host);
    }
  }
  return;
};

1;

=head1 NAME

Object::Remote::Connector::SSH - A connector for SSH servers

=head1 DESCRIPTION

Used to create a connector that talks to an SSH server. Invoked by
L<Object::Remote/connect> if the connection spec looks like a hostname or
user@hostname combo.

=head1 ARGUMENTS

Inherits arguments from L<Object::Remote::Role::Connector::PerlInterpreter> and
provides the following:

=head2 ssh_to

When invoked via L<Object::Remote/connect>, specified via the connection spec,
and not overridable.

String that contains hostname or user@hostname to connect to.

=head2 ssh_options

An arrayref containing a list of strings to be passed to L<IPC::Open3> with
options to be passed specifically to the ssh client. Defaults to C<-A>.

=head2 ssh_command

A string or arrayref of strings with the ssh command to be run. Defaults to
C<ssh>.

=head2 ssh_perl_command

An arrayref containing a list of strings to be passed to L<IPC::Open3> to open
the perl process. Defaults to constructing an ssh client incantation with the
other arguments here.

=cut
