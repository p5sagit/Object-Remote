package Object::Remote::Connector::Local;

use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

push @Object::Remote::Connection::Guess, sub {
  if (($_[0]||'') eq '-') { __PACKAGE__->new->connect }
};

1;
