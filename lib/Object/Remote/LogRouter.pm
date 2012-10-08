package Object::Remote::LogRouter; 

use Moo;
use Scalar::Util qw(blessed);

with 'Object::Remote::Role::LogForwarder';

has subscriptions => ( is => 'ro', required => 1, default => sub { [] } );
has description => ( is => 'rw', required => 1 );

sub before_import { }
sub after_import { }

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
        #TODO issues with caller_level have not been resolved yet
        #when a logger crosses an object::remote::connection so
        $logger = $logger->($caller, { caller_level => -1 });
        
        #TODO there is a known issue with the interaction of this 
        #routed logging scheme and objects proxied with Object::Remote.
        #Specifically the loggers must be invoked with a calling
        #depth of 0 which isn't possible using a logger that has
        #been proxied which is what happens with routed logging
        #if the logger is created in one Perl interpreter and the
        #logging happens in another
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

