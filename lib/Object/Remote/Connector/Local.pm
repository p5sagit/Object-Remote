package Object::Remote::Connector::Local;

use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

no warnings 'once';

BEGIN {  }

push @Object::Remote::Connection::Guess, sub {
  if (($_[0]||'') eq '-') {
      shift(@_);
      __PACKAGE__->new(@_);
  }
};

1;

=head1 NAME

Object::Remote::Connector::Local - A connector for a local Perl process

=head1 ARGUMENTS

Inherits arguments from L<Object::Remote::Role::Connector::PerlInterpreter> and
provides no own arguments.

=cut
