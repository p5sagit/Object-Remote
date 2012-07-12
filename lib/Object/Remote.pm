package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Handle;
use Module::Runtime qw(use_module);

sub new::on {
  my ($class, $on, @args) = @_;
  my $conn = __PACKAGE__->connect($on);
  return $conn->remote_object(class => $class, args => \@args);
}

sub can::on {
  my ($class, $on, $name) = @_;
  my $conn = __PACKAGE__->connect($on);
  return $conn->remote_sub(join('::', $class, $name));
}

sub new {
  shift;
  Object::Remote::Handle->new(@_)->proxy;
}

sub connect {
  my ($class, $to) = @_;
  use_module('Object::Remote::Connection')->new_from_spec($to);
}

sub current_loop {
  our $Current_Loop ||= Object::Remote::MiniLoop->new
}

1;
