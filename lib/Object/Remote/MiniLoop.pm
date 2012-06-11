package Object::Remote::MiniLoop;

use IO::Select;
use Moo;

# this is ro because we only actually set it using local in sub run

has is_running => (is => 'ro', clearer => 'stop');

has _read_watches => (is => 'ro', default => sub { {} });
has _read_select => (is => 'ro', default => sub { IO::Select->new });

sub pass_watches_to {
  my ($self, $new_loop) = @_;
  foreach my $fh ($self->_read_select->handles) {
    $new_loop->watch_io(
      handle => $fh,
      on_read_ready => $self->_read_watches->{$fh}
    );
  }
}

sub watch_io {
  my ($self, %watch) = @_;
  my $fh = $watch{handle};
  if (my $cb = $watch{on_read_ready}) {
    $self->_read_select->add($fh);
    $self->_read_watches->{$fh} = $cb;
  }
}

sub unwatch_io {
  my ($self, %watch) = @_;
  my $fh = $watch{handle};
  if ($watch{on_read_ready}) {
    $self->_read_select->remove($fh);
    delete $self->_read_watches->{$fh};
  }
}

sub loop_once {
  my ($self) = @_;
  my $read = $self->_read_watches;
  my ($readable) = IO::Select->select($self->_read_select, undef, undef, 0.5);
  # I would love to trap errors in the select call but IO::Select doesn't
  # differentiate between an error and a timeout.
  #   -- no, love, mst.
  foreach my $fh (@$readable) {
    $read->{$fh}();
  }
}

sub want_run {
  my ($self) = @_;
  $self->{want_running}++;
}

sub run_while_wanted {
  my ($self) = @_;
  $self->loop_once while $self->{want_running};
}

sub want_stop {
  my ($self) = @_;
  $self->{want_running}-- if $self->{want_running};
}

sub run {
  my ($self) = @_;
  local $self->{is_running} = 1;
  while ($self->is_running) {
    $self->loop_once;
  }
}

1;
