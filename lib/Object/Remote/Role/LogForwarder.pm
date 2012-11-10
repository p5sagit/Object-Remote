package Object::Remote::Role::LogForwarder;

use Moo::Role;

has enable_forward => ( is => 'rw', default => sub { 1 } );
has _forward_destination => ( is => 'rw' );
has _forward_stop => ( is => 'ro', required => 1, default => sub { {} } );

after _deliver_message => sub {
  my ($self, $level, $generator, $args, $metadata) = @_;
  my $package = $metadata->{package};
  my $destination = $self->_forward_destination;
  our $reentrant;

  return unless $self->enable_forward;
  return unless defined $destination;
  return if $self->_forward_stop->{$package};

  if (defined $reentrant) {
    warn "log forwarding went reentrant. bottom: '$reentrant' top: '$package'";
    return;
  }
  
  local $reentrant = $package;
  
  $destination->_deliver_message($level, $generator, $args, $metadata);
};

sub exclude_forwarding {
  my ($self, $package) = @_;
  $package = caller unless defined $package;
  $self->_forward_stop->{$package} = 1;
}

1;
