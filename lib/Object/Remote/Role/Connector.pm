package Object::Remote::Role::Connector;

use Object::Remote::Connection;
use Moo::Role;

requires '_open2_for';

sub connect {
  my $self = shift;
  my %args;
  @args{qw(send_to_fh receive_from_fh child_pid)} = $self->_open2_for(@_);
  my $line = readline($args{receive_from_fh});
  unless ($line eq "Shere\n") {
    die "New remote container did not send Shere - got ${line}";
  }
  return Object::Remote::Connection->new(\%args);
}

1;
