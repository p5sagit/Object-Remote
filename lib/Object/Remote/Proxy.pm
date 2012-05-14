package Object::Remote::Proxy;

use strictures 1;

sub AUTOLOAD {
  my $self = shift;
  (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
  $self->{remote}->call($method => @_);
}

sub DESTROY { }

1;
