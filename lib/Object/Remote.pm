package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Handle;

sub new::on {
  my ($class, $on, @args) = @_;
  Object::Remote::Handle->new(
    connection => $on,
    class => $class,
    args => \@args
  )->proxy;
}

sub new {
  shift;
  Object::Remote::Handle->new(@_)->proxy;
}

sub current_loop {
  our $Current_Loop ||= Object::Remote::MiniLoop->new
}

1;
