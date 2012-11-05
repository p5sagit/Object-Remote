package Object::Remote::Role::LogForwarder;

use Moo::Role;
use Carp qw(cluck);

has _forward_destination => ( is => 'rw' );
has enable_forward => ( is => 'rw', default => sub { 1 } );
has _forward_stop => ( is => 'ro', required => 1, default => sub { {} } );

around _get_loggers => sub {
  my ($orig, $self, %metadata) = @_;
  my $package = $metadata{package};
  my %clone = %metadata;
  our $reentrant;
  
  return if $reentrant;
  local($reentrant) = 1; 
    
  my @loggers = $orig->($self, %clone);

  if (! $self->enable_forward || $self->_forward_stop->{$package}) {
    #warn "will not forward log events for '$package'";
    return @loggers;
  }
  
  my $forward_to = $self->_forward_destination;
  
  if ($forward_to) {
    push(@loggers, $forward_to->_get_loggers(%clone));
  }
  
  return @loggers;
};

sub exclude_forwarding {
    my ($self, $package) = @_;
    $package = caller unless defined $package;
    $self->_forward_stop->{$package} = 1;
}

1;
