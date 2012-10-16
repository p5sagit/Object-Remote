package Object::Remote::LogRouter; 

use Moo;
use Scalar::Util qw(blessed);

with 'Object::Remote::Role::LogForwarder';

has subscriptions => ( is => 'ro', required => 1, default => sub { [] } );
has description => ( is => 'rw', required => 1 );

sub before_import { }
sub after_import { }

sub subscribe {
  my ($self, $logger, $selector) = @_;
  my $subscription_list = $self->subscriptions;
     
  my $subscription = [ $logger, $selector ];
  
  push(@$subscription_list, $subscription);
   
  return $self; 
}

#TODO turn this logic into a role
sub get_loggers {
  my ($self, $caller, $level) = @_; 
  my $should_clean = 0; 
  my @logger_list; 
      
  foreach(@{ $self->subscriptions }) {
    unless(defined) {
      $should_clean = 1;
        next; 
     }
     
     my ($logger, $selector) = @$_;
     
     if ($selector->({ log_level => $level, package => $caller, caller_level => 2 })) {
       push(@logger_list, $logger);     
     }
   }
   
   if ($should_clean) {
     $self->_remove_dead_subscriptions; 
   }
   
   return @logger_list; 
}

sub _remove_dead_subscriptions {
  my ($self) = @_; 
  my @ok = grep { defined $_ } @{$self->subscriptions}; 
  @{$self->subscriptions} = @ok; 
  return; 
}


1; 

