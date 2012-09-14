package Object::Remote::LogRouter; 

use Moo;
use Scalar::Util qw(blessed);

with 'Object::Remote::Role::LogForwarder';

has subscriptions => ( is => 'ro', required => 1, default => sub { [] } );

sub before_import { }
sub after_import {   
   my ($self, $controller, $importer, $config) = @_;
   my $logger = $controller->arg_logger($config->{logger});
   
# TODO need to review this concept, ignore these configuration values for now
#   my $package_logger = $controller->arg_package_logger($config->{package_logger});
#   my $default_logger = $config->{default_logger};
#      
#   #when installing a new selector this will be the default
#   #logger invoked unless otherwise specified
#   $self->{default_logger} = $default_logger;
#
#   #if the logger configuration value is specified 
#   #then all logs given to the router will also be
#   #delivered to that logger
#   if (defined($logger)) {
#      $self->add_selector(sub { 1 }, $logger); 
#   }
#   
#   #if the configuration specifies a package logger
#   #build a selector that matches the package and
#   #install it
#   if (defined($package_logger)) {
#      $self->add_selector( sub { $_->{package} eq $importer }, $package_logger );
#   }
}

sub subscribe {
   my ($self, $logger, $selector, $is_temp) = @_; 
   my $subscription_list = $self->subscriptions;
   
   if(ref $logger ne 'CODE') {
      die 'logger was not a CodeRef or a logger object.  Please try again.'
         unless blessed($logger);
      $logger = do { my $l = $logger; sub { $l } }
   }
  
   my $subscription = [ $logger, $selector ];
  
   $is_temp = 0 unless defined $is_temp; 
   push(@$subscription_list, $subscription);
   if ($is_temp) {
      #weaken($subscription->[-1]);
   }
   return $subscription; 
}

#TODO turn this logic into a role
sub handle_log_message {
   my ($self, $caller, $level, $log_meth, @values) = @_; 
   my $should_clean = 0; 
      
   foreach(@{ $self->subscriptions }) {
      unless(defined($_)) {
         $should_clean = 1;
         next; 
      }
      my ($logger, $selector) = @$_;
      #TODO this is not a firm part of the api but providing
      #this info to the selector is a good feature
      local($_) = { level => $level, package => $caller };
      if ($selector->(@values)) {
         #TODO resolve caller_level issues with routing
         #idea: the caller level will differ in distance from the
         #start of the call stack but it's a constant distance from
         #the end of the call stack - can that be exploited to calculate
         #the distance from the start right before it's used?
         #
         #newer idea: in order for log4perl to work right the logger
         #must be invoked in the exported log_* method directly
         #so by passing the logger down the chain of routers
         #it can be invoked in that location and the caller level
         #problem doesn't exist anymore
         $logger = $logger->($caller, { caller_level => -1 });
         
         $logger->$level($log_meth->(@values))
            if $logger->${\"is_$level"};
      }
   }
   
   if ($should_clean) {
      $self->_remove_dead_subscriptions; 
   }
   
   return; 
}

sub _remove_dead_subscriptions {
   my ($self) = @_; 
   my @ok = grep { defined $_ } @{$self->subscriptions}; 
   @{$self->subscriptions} = @ok; 
   return; 
}


1; 

