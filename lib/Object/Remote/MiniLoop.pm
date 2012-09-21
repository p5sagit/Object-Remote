package Object::Remote::MiniLoop;

use IO::Select;
use Time::HiRes qw(time);
use Object::Remote::Logging qw( :log :dlog );
use Moo;

# this is ro because we only actually set it using local in sub run

has is_running => (is => 'ro', clearer => 'stop');

has _read_watches => (is => 'ro', default => sub { {} });
has _read_select => (is => 'ro', default => sub { IO::Select->new });

has _write_watches => (is => 'ro', default => sub { {} });
has _write_select => (is => 'ro', default => sub { IO::Select->new });

has _timers => (is => 'ro', default => sub { [] });

sub pass_watches_to {
  my ($self, $new_loop) = @_;
  log_debug { "passing watches to new run loop" };
  foreach my $fh ($self->_read_select->handles) {
    $new_loop->watch_io(
      handle => $fh,
      on_read_ready => $self->_read_watches->{$fh}
    );
  }
  foreach my $fh ($self->_write_select->handles) {
    $new_loop->watch_io(
      handle => $fh,
      on_write_ready => $self->_write_watches->{$fh}
    );
  }
}

sub watch_io {
  my ($self, %watch) = @_;
  my $fh = $watch{handle};
  Dlog_debug { "Adding IO watch for $_" } $fh;

  #TODO if this works out non-blocking support
  #will need to be integrated in a way that
  #is compatible with Windows which has no
  #non-blocking support
  if (0) {
    Dlog_warn { "setting file handle to be non-blocking: $_" } $fh;
    use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
    my $flags = fcntl($fh, F_GETFL, 0)
      or die "Can't get flags for the socket: $!\n";
    $flags = fcntl($fh, F_SETFL, $flags | O_NONBLOCK)
      or die "Can't set flags for the socket: $!\n"; 
  }
  
  if (my $cb = $watch{on_read_ready}) {
    log_trace { "IO watcher is registering with select for reading" };
    $self->_read_select->add($fh);
    $self->_read_watches->{$fh} = $cb;
  }
  if (my $cb = $watch{on_write_ready}) {
    log_trace { "IO watcher is registering with select for writing" };
    $self->_write_select->add($fh);
    $self->_write_watches->{$fh} = $cb;
  }
  return;
}

sub unwatch_io {
  my ($self, %watch) = @_;
  my $fh = $watch{handle};
  Dlog_debug { "Removing IO watch for $_" } $fh;
  if ($watch{on_read_ready}) {
    log_trace { "IO watcher is removing read from select()" };
    $self->_read_select->remove($fh);
    delete $self->_read_watches->{$fh};
  }
  if ($watch{on_write_ready}) {
    log_trace { "IO watcher is removing write from select()" };
    $self->_write_select->remove($fh);
    delete $self->_write_watches->{$fh};
  }
  return;
}

sub watch_time {
  my ($self, %watch) = @_;
  my $at = $watch{at} || do {
    die "watch_time requires at or after" unless my $after = $watch{after};
    time() + $after;
  };
  die "watch_time requires code" unless my $code = $watch{code};
  my $timers = $self->_timers;
  my $new = [ $at => $code ];
  @{$timers} = sort { $a->[0] <=> $b->[0] } @{$timers}, $new;
  log_debug { "Created new timer that expires at '$at'" };
  return "$new";
}

sub unwatch_time {
  my ($self, $id) = @_;
  log_debug { "Removing timer with id of '$id'" };
  @$_ = grep !($_ eq $id), @$_ for $self->_timers;
  return;
}

sub _next_timer_expires_delay {
  my ($self) = @_;
  my $timers = $self->_timers;
  #undef means no timeout, select only returns
  #when data is ready - when the system
  #deadlocks the chatter from the timeout in
  #select clogs up the logs
  #TODO should make this an attribute
  my $delay_max = undef;
    
  return $delay_max unless @$timers;
  my $duration = $timers->[0]->[0] - time;

  log_trace { "next timer fires in '$duration' seconds " };
  
  if ($duration < 0) {
    $duration = 0; 
  } elsif (defined $delay_max && $duration > $delay_max) {
    $duration = $delay_max;
  }
  
  return $duration; 
}

sub loop_once {
  my ($self) = @_;
  my $read = $self->_read_watches;
  my $write = $self->_write_watches;
  our $Loop_Entered = 1; 
  my $read_count = 0;
  my $write_count = 0; 
  my @c = caller;
  my $wait_time = $self->_next_timer_expires_delay;
  log_trace {  sprintf("Run loop: loop_once() has been invoked by $c[1]:$c[2] with read:%i write:%i select timeout:%s",
      scalar(keys(%$read)), scalar(keys(%$write)), defined $wait_time ? $wait_time : 'indefinite' ) };
  #TODO The docs state that select() in some instances can return a socket as ready to
  #read data even if reading from it would block and the recomendation is to set
  #handles used with select() as non-blocking but Perl on Windows can not set a 
  #handle to use non-blocking IO - If Windows is not one of the operating
  #systems where select() returns a handle that could block it would work to
  #enable non-blocking mode only under Posix - the non-blocking sysread()
  #logic would work unmodified for both blocking and non-blocking handles
  #under Posix and Windows.
  my ($readable, $writeable) = IO::Select->select(
    #TODO how come select() isn't used to identify handles with errors on them?
    #TODO is there a specific reason for a half second maximum wait duration?
    #The two places I've found for the runloop to be invoked don't return control
    #to the caller until a controlling variable interrupts the loop that invokes
    #loop_once() - is this to allow that variable to be polled and exit the
    #run loop? If so why isn't that behavior event driven and causes select() to
    #return? 
    $self->_read_select, $self->_write_select, undef, $wait_time
  ); 
  log_trace { 
    my $readable_count = defined $readable ? scalar(@$readable) : 0;
    my $writable_count = defined $writeable ? scalar(@$writeable) : 0;
    "Run loop: select returned readable:$readable_count writeable:$writable_count";
  };
  # I would love to trap errors in the select call but IO::Select doesn't
  # differentiate between an error and a timeout.
  #   -- no, love, mst.

  local $Loop_Entered;

  log_trace { "Reading from all ready filehandles" };
  foreach my $fh (@$readable) {
    next unless $read->{$fh};
    $read_count++;
    $read->{$fh}();
    last if $Loop_Entered;
#    $read->{$fh}() if $read->{$fh};
  }
  log_trace { "Writing to all ready filehandles" };
  foreach my $fh (@$writeable) {
    next unless $write->{$fh};
    $write_count++;
    $write->{$fh}();
    last if $Loop_Entered;
#    $write->{$fh}() if $write->{$fh};
  }
  log_trace { "Read from $read_count filehandles; wrote to $write_count filehandles" };
  my $timers = $self->_timers;
  my $now = time();
  log_trace { "Checking timers" };
  while (@$timers and $timers->[0][0] <= $now) {
    Dlog_debug { "Found timer that needs to be executed: $_" } $timers->[0];
    (shift @$timers)->[1]->();
    last if $Loop_Entered;
  }
  log_trace { "Run loop: single loop is completed" };
  return;
}

#::Node and ::ConnectionServer use the want_run() / want_stop()
#counter to cause a run-loop to execute while something is active;
#the futures do this via a different mechanism
sub want_run {
  my ($self) = @_;
  Dlog_debug { "Run loop: Incrimenting want_running, is now $_" }
    ++$self->{want_running};
}

sub run_while_wanted {
  my ($self) = @_;
  log_debug { my $wr = $self->{want_running}; "Run loop: run_while_wanted() invoked; want_running: $wr" };
  $self->loop_once while $self->{want_running};
  log_debug { "Run loop: run_while_wanted() completed" };
  return;
}

sub want_stop {
  my ($self) = @_;
  if (! $self->{want_running}) {
    log_debug { "Run loop: want_stop() was called but want_running was not true" };
    return; 
  }
  Dlog_debug { "Run loop: decrimenting want_running, is now $_" }
    --$self->{want_running};
}

#TODO Hypothesis: Futures invoke run() which gives that future
#it's own localized is_running attribute - any adjustment to the
#is_running attribute outside of that future will not effect that
#future so each future winds up able to call run() and stop() at 
#will with out interfering with each other 
sub run {
  my ($self) = @_;
  log_trace { "Run loop: run() invoked" };
  local $self->{is_running} = 1;
  while ($self->is_running) {
    $self->loop_once;
  }
  log_trace { "Run loop: run() completed" };
  return;
}

1;
