package Object::Remote::LogDestination;

use Moo; 
use Scalar::Util qw(weaken);

has logger => ( is => 'ro', required => 1 );
has subscriptions => ( is => 'ro', required => 1, default => sub { [] } ); 

sub select {
   my ($self, $router, $selector) = @_; 
   my $subscription = $router->subscribe($self->logger, $selector); 
   push(@{ $self->subscriptions }, $subscription);
   return $subscription; 
}

sub connect {
   my ($self, $router) = @_; 
   return $self->select($router, sub { 1 });
}

1; 


