package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Proxy;
use Scalar::Util qw(weaken);
use Moo;

has connection => (is => 'ro', required => 1);

has id => (is => 'rwp');

has disarmed_free => (is => 'rwp');

sub disarm_free { $_[0]->_set_disarmed_free(1); $_[0] }

sub proxy {
  bless({ remote => $_[0], method => 'call' }, 'Object::Remote::Proxy');
}

sub BUILD {
  my ($self, $args) = @_;
  unless ($self->id) {
    die "No id supplied and no class either" unless $args->{class};
    $self->_set_id(
      $self->_await(
        $self->connection->send(
          class_call => $args->{class},
          $args->{constructor}||'new', @{$args->{args}||[]}
        )
      )->{remote}->disarm_free->id
    );
  }
  $self->connection->register_remote($self);
}

sub current_loop {
  our $Current_Loop ||= Object::Remote::MiniLoop->new
}

sub call {
  my ($self, $method, @args) = @_;
  $self->_await($self->connection->send(call => $self->id, $method, @args));
}

sub call_discard {
  my ($self, $method, @args) = @_;
  $self->connection->send_discard(call => $self->id, $method, @args);
}

sub _await {
  my ($self, $future) = @_;
  my $loop = $self->current_loop;
  $future->on_ready(sub { $loop->stop });
  $loop->run;
  ($future->get)[0];
}

sub DEMOLISH {
  my ($self, $gd) = @_;
  return if $gd or $self->disarmed_free;
  $self->connection->send_free($self->id);
}

1;
