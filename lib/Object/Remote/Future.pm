package Object::Remote::Future;

use strict;
use warnings;
use base qw(Exporter);

use CPS::Future;

our @EXPORT = qw(future await_future await_all);

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

sub await_all {
  await_future(CPS::Future->needs_all(@_));
  map $_->get, @_;
}

package start;

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /^start::(.+)$/;
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

1;

=head1 NAME

Object::Remote::Future - Asynchronous calling for L<Object::Remote>

=head1 LAME

Shipping prioritised over writing this part up. Blame mst.

=cut
