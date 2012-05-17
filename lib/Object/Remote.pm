package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Proxy;
use Scalar::Util qw(weaken blessed);
use Module::Runtime qw(use_module);
use Moo;

sub new::on {
  my ($class, $on, @args) = @_;
  __PACKAGE__->new(
    connection => $on,
    class => $class,
    args => \@args
  )->proxy;
}

has connection => (
  is => 'ro', required => 1,
  coerce => sub {
    blessed($_[0])
      ? $_[0]
      : use_module('Object::Remote::Connection')->new_from_spec($_[0])
  },
);

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
    ref($_) eq 'HASH' and $_ = [ %$_ ] for $args->{args};
    $self->_set_id(
      $self->_await(
        $self->connection->send(
          class_call => $args->{class}, 0,
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
  $self->_await(
    $self->connection->send(call => $self->id, wantarray, $method, @args)
  );
}

sub call_discard {
  my ($self, $method, @args) = @_;
  $self->connection->send_discard(call => $self->id, $method, @args);
}

sub call_discard_free {
  my ($self, $method, @args) = @_;
  $self->disarm_free;
  $self->connection->send_discard(call_free => $self->id, $method, @args);
}

sub _await {
  my ($self, $future) = @_;
  my $loop = $self->current_loop;
  $future->on_ready(sub { $loop->stop });
  $loop->run;
  wantarray ? $future->get : ($future->get)[0];
}

sub DEMOLISH {
  my ($self, $gd) = @_;
  return if $gd or $self->disarmed_free;
  $self->connection->send_free($self->id);
}

1;
