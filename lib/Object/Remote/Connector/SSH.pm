package Object::Remote::Connector::SSH;

use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

has ssh_to => (is => 'ro', required => 1);

around _perl_command => sub {
  my ($orig, $self) = @_;
  return 'ssh', '-A', $self->ssh_to, $self->$orig;
};

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
