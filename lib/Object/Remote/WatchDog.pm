package Object::Remote::WatchDog; 

use Object::Remote::MiniLoop; 
use Object::Remote::Logging qw ( :log :dlog );
use Moo; 

has timeout => ( is => 'ro', required => 1 );

around new => sub {
  my ($orig, $self, @args) = @_; 
  our ($WATCHDOG);
    
  return $WATCHDOG if defined $WATCHDOG;
  log_trace { "Constructing new instance of global watchdog" };
  return $WATCHDOG = $self->$orig(@args);    
};

#start the watchdog
sub BUILD {
  my ($self) = @_;
  
  $SIG{ALRM} = sub {
    #if the Watchdog is killing the process we don't want any chance of the
    #process not actually exiting and die could be caught by an eval which
    #doesn't do us any good 
    log_error { sprintf("Watchdog has expired, terminating the process at file %s line %s", __FILE__, __LINE__ + 1); };
    exit(1);     
  };   
  
  Dlog_debug { "Initializing watchdog with timeout of $_ seconds" } $self->timeout;
  alarm($self->timeout);
}

#invoke at least once per timeout to stop
#the watchdog from killing the process 
sub reset {
  our ($WATCHDOG);
  die "Attempt to reset the watchdog before it was constructed"
    unless defined $WATCHDOG; 
  
  log_trace { "Watchdog has been reset" };
  alarm($WATCHDOG->timeout); 
}

#must explicitly call this method to stop the
#watchdog from killing the process - if the
#watchdog is lost because it goes out of scope
#it makes sense to still terminate the process
sub shutdown {
  my ($self) = @_;
  alarm(0); 
}

1;


