package Object::Remote::Role::Connector;

use Module::Runtime qw(use_module);
use Moo::Role;

requires '_open2_for';

sub connect {
  my $self = shift;
  my %args;
  @args{qw(send_to_fh receive_from_fh child_pid)} = $self->_open2_for(@_);
  return use_module('Object::Remote::Connection')->new(\%args);
}

1;
