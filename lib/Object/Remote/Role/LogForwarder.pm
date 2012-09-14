package Object::Remote::Role::LogForwarder;

use Moo::Role; 

with 'Log::Contextual::Role::Router';

#TODO re-weaken router references when object::remote
#weak reference operation is figured out

has child_routers => ( is => 'ro', required => 1, default => sub { {} } );
has parent_router => ( is => 'rw', );#weak_ref => 1 );

#adds a child router to this router and gives it
#a friendly display name
sub add_child_router {
   my ($self, $description, $router) = @_;
   $self->child_routers->{$description} = $router;
   #weaken($self->child_routers->{$class});
   $router->parent_router($self);
   return; 
}

sub remove_child_router {
   my ($self, $description) = @_;
   return delete $self->child_routers->{$description};
}

after handle_log_message => sub {
   my ($self, @args) = @_;
   my $parent = $self->parent_router;
      
   return unless defined $parent;
   $parent->handle_log_message(@args);
};

1;
