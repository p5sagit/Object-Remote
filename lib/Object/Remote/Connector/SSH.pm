package Object::Remote::Connector::SSH;

use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

around _perl_command => sub {
  my ($orig, $self, $target) = @_;
  return 'ssh', '-A', $target, $self->$orig($target);
};

no warnings 'once';

push @Object::Remote::Connection::Guess, sub { 
  for ($_[0]) {
    # 0-9 a-z _ - first char, those or . subsequent - hostnamish
    if (defined and !ref and /^(?:.*?\@)?[\w\-][\w\-\.]/) {
      return __PACKAGE__->new->connect($_[0]);
    }
  }
  return;
};

1;
