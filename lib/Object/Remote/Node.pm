package Object::Remote::Node;

use strictures 1;
use Object::Remote::Connector::STDIO;
use Object::Remote::Logging qw(:log :dlog);
use Object::Remote::WatchDog;
use Object::Remote;
use CPS::Future;

sub run {
  my ($class, %args) = @_; 
  log_trace { "run() has been invoked on remote node" };
    
  my $c = Object::Remote::Connector::STDIO->new->connect;
  
  $c->register_class_call_handler;

  my $loop = Object::Remote->current_loop;
  
  $c->on_close->on_ready(sub { 
    log_info { "Node connection with call handler has closed" };
    $loop->want_stop 
  });

  Dlog_trace { "Node is sending 'Shere' to $_" } $c->send_to_fh;
  print { $c->send_to_fh } "Shere\n";

  log_debug { "Node is going to start the run loop" };
  if ($args{watchdog_timeout}) {
    Object::Remote::WatchDog->new(timeout => $args{watchdog_timeout});
  } else {
    #reset connection watchdog from the fatnode
    alarm(0);
  }
  $loop->want_run;
  $loop->run_while_wanted;
  log_debug { "Run loop invocation in node has completed" };
}

1;
