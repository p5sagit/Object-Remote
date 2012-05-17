package Object::Remote::Proxy;

use strictures 1;

sub AUTOLOAD {
  my $self = shift;
  (my $method) = (our $AUTOLOAD =~ /([^:]+)$/);
  if ((caller(0)||'') eq 'start') {
    $method = "start::${method}";
  }
  $self->{remote}->${\$self->{method}}($method => @_);
}

sub DESTROY { }

1;
