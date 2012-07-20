package Object::Remote::Connector::SSH;

use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

has ssh_to => (is => 'ro', required => 1);

has ssh_perl_command => (is => 'lazy');

sub _build_ssh_perl_command {
  my ($self) = @_;
  return [ 'ssh', '-A', $self->ssh_to, @{$self->perl_command} ];
}

sub final_perl_command { shift->ssh_perl_command }

no warnings 'once';

push @Object::Remote::Connection::Guess, sub { 
  for ($_[0]) {
    # 0-9 a-z _ - first char, those or . subsequent - hostnamish
    if (defined and !ref and /^(?:.*?\@)?[\w\-][\w\-\.]/) {
      return __PACKAGE__->new(ssh_to => $_[0]);
    }
  }
  return;
};

1;
