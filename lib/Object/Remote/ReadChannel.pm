package Object::Remote::ReadChannel;

use CPS::Future;
use Scalar::Util qw(weaken);
use Object::Remote::Logging qw(:log :dlog);
use Moo;

has fh => (
  is => 'ro', required => 1,
  trigger => sub {
    my ($self, $fh) = @_;
    weaken($self);
    log_trace { "Watching filehandle via trigger on 'fh' attribute in Object::Remote::ReadChannel" };
    Object::Remote->current_loop
                  ->watch_io(
                      handle => $fh,
                      on_read_ready => sub { $self->_receive_data_from($fh) }
                    );
  },
);

has on_close_call => (
  is => 'rw', default => sub { sub {} },
);

has on_line_call => (is => 'rw');

has _receive_data_buffer => (is => 'ro', default => sub { my $x = ''; \$x });

#TODO confirmed this is the point of the hang - sysread() is invoked on a 
#socket inside the controller that blocks and deadlocks the entire system.
#The remote nodes are all waiting to receive data at that point.
#Validated this behavior exists in an unmodified Object::Remote from CPAN 
#by wrapping this sysread() with warns that have the pid in them and pounding 
#my local machine with System::Introspector via ssh and 7 remote perl instances
#It looks like one of the futures is responding to an event regarding the ability
#to read from a socket and every once in a while an ordering issue means that
#there is no actual data to read from the socket
sub _receive_data_from {
  my ($self, $fh) = @_;
  Dlog_trace { "Preparing to read data from $_" } $fh;
  #use Carp qw(cluck); cluck();
  my $rb = $self->_receive_data_buffer;
  #TODO is there a specific reason sysread() and syswrite() aren't
  #a part of ::MiniLoop? It's one spot to handle errors and other
  #logic involving filehandles
  my $len = sysread($fh, $$rb, 32768, length($$rb));
  my $err = defined($len) ? '' : ": $!";
  if (defined($len) and $len > 0) {
    log_trace { "Read $len bytes of data" };
    while (my $cb = $self->on_line_call and $$rb =~ s/^(.*)\n//) {
      $cb->(my $line = $1);
    }
  } else {
    log_trace { "Got EOF or error, this read channel is done" };
    Object::Remote->current_loop
                  ->unwatch_io(
                      handle => $self->fh,
                      on_read_ready => 1
                    );
    $self->on_close_call->($err);
  }
}

sub DEMOLISH {
  my ($self, $gd) = @_;
  return if $gd;
  log_trace { "read channel is being demolished" };
  Object::Remote->current_loop
                ->unwatch_io(
                    handle => $self->fh,
                    on_read_ready => 1
                  );
}

1;
