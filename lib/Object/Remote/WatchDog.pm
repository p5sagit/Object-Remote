package Object::Remote::WatchDog;

use Object::Remote::MiniLoop;
use Object::Remote::Logging qw (:log :dlog router);
use Moo;

has timeout => ( is => 'ro', required => 1 );

BEGIN { router()->exclude_forwarding; }

sub instance {
  my ($class, @args) = @_;

  return our $WATCHDOG ||= do {
    log_trace { "Constructing new instance of global watchdog" };
    $class->new(@args);
  };
};

#start the watchdog
sub BUILD {
  my ($self) = @_;

  $SIG{ALRM} = sub {
    #if the Watchdog is killing the process we don't want any chance of the
    #process not actually exiting and die could be caught by an eval which
    #doesn't do us any good
    log_fatal { "Watchdog has expired, terminating the process" };
    exit(1);
  };

  Dlog_debug { "Initializing watchdog with timeout of $_ seconds" } $self->timeout;
  alarm($self->timeout);
}

#invoke at least once per timeout to stop
#the watchdog from killing the process
sub reset {
  die "Attempt to reset the watchdog before it was constructed"
    unless defined our $WATCHDOG;

  log_debug { "Watchdog has been reset" };
  alarm($WATCHDOG->timeout);
}

#must explicitly call this method to stop the
#watchdog from killing the process - if the
#watchdog is lost because it goes out of scope
#it makes sense to still terminate the process
sub shutdown {
  my ($self) = @_;
  log_debug { "Watchdog is shutting down" };
  alarm(0);
}

1;

=head1 NAME

Object::Remote::WatchDog - alarm-based event loop timeout singleton

=head1 DESCRIPTION

This is a singleton class intended to be used in remote nodes to kill the
process if the event loop seems to have stalled for longer than the timeout
specified.

=head1 METHODS

The following are all class methods.

=head2 instance

  my $d = Object::Remote::WatchDog->instance(timeout => 10);

Creates a new watch dog if there wasn't one yet, with the timeout set to the
specified value. The timeout argument is required. The timeout is immediately
started by calling C<alarm> with the timeout specified. The C<ALRM> signal is
replaced with a handler that, when triggered, quits the process with an error.

If there already was a watchdog it just returns that, however in that case the
timeout value is ignored.

=head2 reset

  Object::Remote::WatchDog->reset;

Calls C<alarm> with the timeout value of the current watch dog singleton to
reset it. Throws an exception if there is no current singleton. Intended to be
called repeatedly by the event loop to signal it's still running and not
stalled.

=head2 shutdown

  Object::Remote::WatchDog->shutdown;

Sets C<alarm> back to 0, thus preventing the C<ALRM> handler from quitting the
process.

=cut


