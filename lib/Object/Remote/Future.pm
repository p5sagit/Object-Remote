package Object::Remote::Future;

use strict;
use warnings;
use base qw(Exporter);

use Object::Remote::Logging qw( :log get_router );

BEGIN { get_router()->exclude_forwarding }

use CPS::Future;

our @EXPORT = qw(future await_future await_all);

sub future (&;$) {
  my $f = $_[0]->(CPS::Future->new);
  return $f if ((caller(1+($_[1]||0))||'') eq 'start');
  await_future($f);
}

our @await;

sub await_future {
  my $f = shift;
  log_trace { my $ir = $f->is_ready; "await_future() invoked; is_ready: $ir" };
  return $f if $f->is_ready;
  require Object::Remote;
  my $loop = Object::Remote->current_loop;
  {
    local @await = (@await, $f);
    $f->on_ready(sub {
      log_trace { my $l = @await; "future has become ready, length of \@await: '$l'" };
      if ($f == $await[-1]) {
        log_trace { "This future is not waiting on anything so calling stop on the run loop" };
        $loop->stop;         
      }
    });
    log_trace { "Starting run loop for newly created future" };
    $loop->run;
  }
  if (@await and $await[-1]->is_ready) {
    log_trace { "Last future in await list was ready, stopping run loop" };
    $loop->stop;
  }
  log_trace { "await_future() returning" };
  return wantarray ? $f->get : ($f->get)[0];
}

sub await_all {
  log_trace { my $l = @_; "await_all() invoked with '$l' futures to wait on" };
  await_future(CPS::Future->wait_all(@_));
  map $_->get, @_;
}

package start;

our $start = sub { my ($obj, $call) = (shift, shift); $obj->$call(@_); };

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /^start::(.+)$/;
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

package maybe;

sub start {
  my ($obj, $call) = (shift, shift);
  if ((caller(1)||'') eq 'start') {
    $obj->$start::start($call => @_);
  } else {
    $obj->$call(@_);
  }
}

package maybe::start;

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /^maybe::start::(.+)$/;
  $method = "start::${method}" if ((caller(1)||'') eq 'start');
  $invocant->$method(@_);
}

package then;

sub AUTOLOAD {
  my $invocant = shift;
  my ($method) = our $AUTOLOAD =~ /^then::(.+)$/;
  my @args = @_;
  # Need two copies since if we're called on an already complete future
  # $f will be freed immediately
  my $ret = my $f = CPS::Future->new;
  $invocant->on_fail(sub { $f->fail(@_); undef($f); });
  $invocant->on_done(sub {
    my ($obj) = @_;
    my $next = $obj->${\"start::${method}"}(@args);
    $next->on_done(sub { $f->done(@_); undef($f); });
    $next->on_fail(sub { $f->fail(@_); undef($f); });
  });
  return $ret;
}

1;

=head1 NAME

Object::Remote::Future - Asynchronous calling for L<Object::Remote>

=head1 LAME

Shipping prioritised over writing this part up. Blame mst.

=cut
