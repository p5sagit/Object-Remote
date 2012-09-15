package Object::Remote::MiniLoop;

use IO::Select;
use Time::HiRes qw(time);
use Object::Remote::Logging qw( :log );
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
  log_debug { my $type = ref($fh); "Adding watch for ref of type '$type'" };
  if (my $cb = $watch{on_read_ready}) {
    $self->_read_select->add($fh);
    $self->_read_watches->{$fh} = $cb;
  }
  if (my $cb = $watch{on_write_ready}) {
    $self->_write_select->add($fh);
    $self->_write_watches->{$fh} = $cb;
  }
  return;
}

sub unwatch_io {
  my ($self, %watch) = @_;
  my $fh = $watch{handle};
  log_debug { my $type = ref($fh); "Removing watch for ref of type '$type'" };
  if ($watch{on_read_ready}) {
    $self->_read_select->remove($fh);
    delete $self->_read_watches->{$fh};
  }
  if ($watch{on_write_ready}) {
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
  log_debug { "Created new timer with id of '$new' that expires at '$at'" };
  return "$new";
}

sub unwatch_time {
  my ($self, $id) = @_;
  log_debug { "Removing timer with id of '$id'" };
  @$_ = grep !($_ eq $id), @$_ for $self->_timers;
  return;
}

sub loop_once {
  my ($self) = @_;
  my $read = $self->_read_watches;
  my $write = $self->_write_watches;
  my @c = caller;
  log_trace {  sprintf("Run loop: loop_once() has been invoked by $c[1]:$c[2] with read:%i write:%i", scalar(keys(%$read)), scalar(keys(%$write))) };
  my ($readable, $writeable) = IO::Select->select(
    $self->_read_select, $self->_write_select, undef, 0.5
  );
  log_debug { 
      my $readable_count = defined $readable ? scalar(@$readable) : 0;
      my $writable_count = defined $writeable ? scalar(@$writeable) : 0;
      "run loop has readable:$readable_count writeable:$writable_count";
  };
  # I would love to trap errors in the select call but IO::Select doesn't
  # differentiate between an error and a timeout.
  #   -- no, love, mst.
  log_trace { "Reading from all ready filehandles" };
  foreach my $fh (@$readable) {
    $read->{$fh}() if $read->{$fh};
  }
  log_trace { "Writing to all ready filehandles" };
  foreach my $fh (@$writeable) {
    $write->{$fh}() if $write->{$fh};
  }
  my $timers = $self->_timers;
  my $now = time();
  log_trace { "Checking timers" };
  while (@$timers and $timers->[0][0] <= $now) {
    (shift @$timers)->[1]->();
  }
  log_debug { "Run loop: single loop is completed" };
  return;
}

sub want_run {
  my ($self) = @_;
  $self->{want_running}++;
}

sub run_while_wanted {
  my ($self) = @_;
  log_debug { "Run loop: run_while_wanted() invoked" };
  $self->loop_once while $self->{want_running};
  log_debug { "Run loop: run_while_wanted() completed" };
  return;
}

sub want_stop {
  my ($self) = @_;
  $self->{want_running}-- if $self->{want_running};
}

sub run {
  my ($self) = @_;
  log_info { "Run loop: run() invoked" };
  local $self->{is_running} = 1;
  while ($self->is_running) {
    $self->loop_once;
  }
  log_info { "Run loop: run() completed" };
  return;
}

1;
