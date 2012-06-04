package Object::Remote;

use Object::Remote::MiniLoop;
use Object::Remote::Handle;
use Module::Runtime qw(use_module);

sub new::on {
  my ($class, $on, @args) = @_;
  my $conn = use_module('Object::Remote::Connection')->new_from_spec($on);
  return $conn->new_remote(class => $class, args => \@args);
}

sub new {
  shift;
  Object::Remote::Handle->new(@_)->proxy;
}

sub current_loop {
  our $Current_Loop ||= Object::Remote::MiniLoop->new
}

1;
