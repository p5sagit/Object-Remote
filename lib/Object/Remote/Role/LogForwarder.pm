#This is an experimental method for working with
#Log::Contextual crossing Object::Remote connections
#transparently 

package Object::Remote::Role::LogForwarder;

use Moo::Role; 
use Scalar::Util qw(weaken);
use Carp qw(cluck);

with 'Log::Contextual::Role::Router';

#TODO re-weaken router references when object::remote
#weak reference operation is figured out

has child_routers => ( is => 'ro', required => 1, default => sub { [] } );
has parent_router => ( is => 'rw', );#weak_ref => 1 );

sub BUILD { }

after BUILD => sub {
  my ($self) = @_; 
#  my $parent = $self->parent_router; 
#  return unless defined $parent ; 
#  $parent->add_child_router($self);
};

sub describe {
  my ($self, $depth) = @_; 
  $depth = -1 unless defined $depth; 
  $depth++;
  my $buf = "\t" x $depth . $self->description . "\n";
  foreach my $child (@{$self->child_routers}) {
    next unless defined $child; 
    $buf .= $child->describe($depth);
  }
    
  return $buf; 
}

sub add_child_router {
  my ($self, $router) = @_;
  push(@{ $self->child_routers }, $router);
  #TODO re-weaken when object::remote proxied
  #weak references is figured out
#   weaken(${ $self->child_routers }[-1]);
  return; 
}

#sub remove_child_router {
#  my ($self, $description) = @_;
#  return delete $self->child_routers->{$description};
#}

after get_loggers => sub {
  my ($self, @args) = @_;
  my $parent = $self->parent_router;
      
  return unless defined $parent;
  $parent->handle_log_message(@args);
};

1;

