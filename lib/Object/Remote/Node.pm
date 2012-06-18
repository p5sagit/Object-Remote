package Object::Remote::Node;

use strictures 1;
use Object::Remote::Connector::STDIO;
use Object::Remote;
use CPS::Future;

sub run {

  my $c = Object::Remote::Connector::STDIO->new->connect;

  $c->register_class_call_handler;

  $c->ready_future->done;

  my $loop = Object::Remote->current_loop;

  my $f = CPS::Future->new;

  $f->on_ready(sub { $loop->want_stop });

  $c->on_close($f);

  print { $c->send_to_fh } "Shere\n";

  $loop->want_run;
  $loop->run_while_wanted;
}

1;
