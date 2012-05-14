package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Proxy;
use Scalar::Util qw(weaken);
use Moo;

has connection => (is => 'ro', required => 1);

has id => (is => 'rwp');

has proxy => (is => 'lazy', weak_ref => 1);

sub _build_proxy {
  bless({ remote => $_[0] }, 'Object::Remote::Proxy');
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
      )
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

sub _await {
  my ($self, $future) = @_;
  my $loop = $self->current_loop;
  $future->on_ready(sub { $loop->stop });
  $loop->run;
  $future->get;
}

sub DEMOLISH {
  my ($self, $gd) = @_;
  return if $gd;
  $self->connection->send_free($self->id);
}

1;
