package Object::Remote::Future;

use strict;
use warnings;
use base qw(Exporter);

use CPS::Future;

our @EXPORT = qw(future await_future);

sub future (&) {
  my $f = $_[0]->(CPS::Future->new);
  return $f if ((caller(1)||'') eq 'start');
  await_future($f);
}

sub await_future {
  my $f = shift;
  return $f if $f->is_ready;
  require Object::Remote;
  my $loop = Object::Remote->current_loop;
  $f->on_ready(sub { $loop->stop });
  $loop->run;
  return wantarray ? $f->get : ($f->get)[0];
}

package start;

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /([^:]+)$/;
  if (ref($invocant) eq 'ARRAY') {
    return [ map $_->${\"start::${method}"}, @$invocant ];
  }
  my $res;
  unless (eval { $res = $invocant->$method(@_); 1 }) {
    my $f = CPS::Future->new;
    $f->fail($@);
    return $f;
  }
  unless (Scalar::Util::blessed($res) and $res->isa('CPS::Future')) {
    my $f = CPS::Future->new;
    $f->done($res);
    return $f;
  }
  return $res;
}

package await;

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /([^:]+)$/;
  my @invocants = (ref($invocant) eq 'ARRAY' ? @$invocant : $invocant);
  my @futures = map $_->${\"start::${method}"}, @$invocant;
  Object::Remote::Future::await_future(CPS::Future->needs_all(@futures));
  return map $_->get, @futures;
}

1;
