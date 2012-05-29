package Object::Remote::Connector::LocalSudo;

use Moo;

extends 'Object::Remote::Connector::Local';

around _perl_command => sub {
  my ($orig, $self, $target_user) = @_;
  return 'sudo', '-u', $target_user, $self->$orig($target_user);
};

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    # username followed by @
    if (defined and !ref and /^ ([^\@]*?) \@ $/x) {
      return __PACKAGE__->new->connect($1);
    }
  }
  return;
};

1;
