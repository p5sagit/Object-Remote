package Object::Remote::Connection;

use Object::Remote::Logging qw (:log :dlog get_router);
use Object::Remote::Future;
use Object::Remote::Null;
use Object::Remote::Handle;
use Object::Remote::CodeContainer;
use Object::Remote::GlobProxy;
use Object::Remote::GlobContainer;
use Object::Remote::Tied;
use Object::Remote;
use Symbol;
use IO::Handle;
use POSIX ":sys_wait_h";
use Module::Runtime qw(use_module);
use Scalar::Util qw(weaken blessed refaddr openhandle);
use JSON::PP qw(encode_json);
use Moo;

BEGIN { 
  get_router()->exclude_forwarding;

  #this will reap child processes as soon
  #as they are done executing so the process
  #table cleans up as fast as possible but
  #anything that needs to call waitpid()
  #in the future to get the exit value of
  #a child will get trash results if
  #the signal handler was running. 
  #If creating a child and getting the
  #exit value is required then set
  #a localized version of the signal
  #handler for CHLD to be 'IGNORE'
  #in the smallest block possible
  #and outside the block send
  #the process a CHLD signal
  #to reap anything that may
  #have exited while blocked
  #in waitpid() 
  $SIG{CHLD} = sub { 
    my $kid; 
    log_trace { "CHLD signal handler is executing" };
    do {
      $kid = waitpid(-1, WNOHANG);
      log_debug { "waitpid() returned '$kid'" };
    } while $kid > 0;
    log_trace { "CHLD signal handler is done" };
  };
  
  $SIG{PIPE} = sub { log_debug { "Got a PIPE signal" } };      
}

END {
  log_debug { "Killing all child processes in the process group" };
    
  #send SIGINT to the process group for our children
  kill(1, -2);
}

has _id => ( is => 'ro', required => 1, default => sub { our $NEXT_CONNECTION_ID++ } );

has send_to_fh => (
  is => 'ro', required => 1,
  trigger => sub {
      my $self = $_[0];
      $_[1]->autoflush(1);
      Dlog_trace { my $id = $self->_id; "connection had send_to_fh set to $_"  } $_[1];
  },
);

has read_channel => (
  is => 'ro', required => 1,
  trigger => sub {
    my ($self, $ch) = @_;
    my $id = $self->_id; 
    Dlog_trace { "trigger for read_channel has been invoked for connection $id; file handle is $_" } $ch->fh; 
    weaken($self);
    $ch->on_line_call(sub { $self->_receive(@_) });
    $ch->on_close_call(sub { 
      log_trace { "invoking 'done' on on_close handler for connection id '$id'" }; 
      $self->on_close->done(@_);
    });
  },
);

has on_close => (
  is => 'rw', default => sub { $_[0]->_install_future_handlers(CPS::Future->new) },
  trigger => \&_install_future_handlers,
);

has child_pid => (is => 'ro');

has local_objects_by_id => (
  is => 'ro', default => sub { {} },
  coerce => sub { +{ %{$_[0]} } }, # shallow clone on the way in
);

has remote_objects_by_id => (
  is => 'ro', default => sub { {} },
  coerce => sub { +{ %{$_[0]} } }, # shallow clone on the way in
);

has outstanding_futures => (is => 'ro', default => sub { {} });

has _json => (
  is => 'lazy',
  handles => {
    _deserialize => 'decode',
    _encode => 'encode',
  },
);

after BUILD => sub {
  my ($self) = @_; 
  
  return unless defined $self->child_pid; 
  
  log_debug { "Setting process group of child process" };
  
  setpgrp($self->child_pid, 1);
};

sub BUILD { }

sub _fail_outstanding {
  my ($self, $error) = @_;
  Dlog_debug { "Failing outstanding futures with '$error' for connection $_" } $self->_id;
  my $outstanding = $self->outstanding_futures;
  $_->fail("$error\n") for values %$outstanding;
  %$outstanding = ();
  return;
}

sub _install_future_handlers {
    my ($self, $f) = @_;
    Dlog_trace { "trigger for on_close has been invoked for connection $_" } $self->_id;
    weaken($self);
    $f->on_done(sub {
      Dlog_trace { "failing all of the outstanding futures for connection $_" } $self->_id;
      $self->_fail_outstanding("Object::Remote connection lost: " . ($f->get)[0]);
    });
    return $f; 
};

sub _id_to_remote_object {
  my ($self, $id) = @_;
  Dlog_trace { "fetching proxy for remote object with id '$id' for connection $_" } $self->_id;
  return bless({}, 'Object::Remote::Null') if $id eq 'NULL';
  (
    $self->remote_objects_by_id->{$id}
    or Object::Remote::Handle->new(connection => $self, id => $id)
  )->proxy;
}

sub _build__json {
  weaken(my $self = shift);
  JSON::PP->new->filter_json_single_key_object(
    __remote_object__ => sub {
      $self->_id_to_remote_object(@_);
    }
  )->filter_json_single_key_object(
    __remote_code__ => sub {
      my $code_container = $self->_id_to_remote_object(@_);
      sub { $code_container->call(@_) };
    }
  )->filter_json_single_key_object(
    __scalar_ref__ => sub {
      my $value = shift;
      return \$value;
    }
  )->filter_json_single_key_object(
    __glob_ref__ => sub {
      my $glob_container = $self->_id_to_remote_object(@_);
      my $handle = Symbol::gensym;
      tie *$handle, 'Object::Remote::GlobProxy', $glob_container;
      return $handle;
    }
  )->filter_json_single_key_object(
    __local_object__ => sub {
      $self->local_objects_by_id->{$_[0]}
    }
  )->filter_json_single_key_object(
    __remote_tied_hash__ => sub {
      my %tied_hash;
      tie %tied_hash, 'Object::Remote::Tied', $self->_id_to_remote_object(@_);
      return \%tied_hash;
    }
  )->filter_json_single_key_object(
    __remote_tied_array__ => sub {
      my @tied_array;
      tie @tied_array, 'Object::Remote::Tied', $self->_id_to_remote_object(@_);
      return \@tied_array;
    }
  ); 
}

sub _load_if_possible {
  my ($class) = @_; 

  use_module($class); 

  if ($@) {
    log_debug { "Attempt at loading '$class' failed with '$@'" };
  }

}

BEGIN {
  unshift our @Guess, sub { blessed($_[0]) ? $_[0] : undef };
  map _load_if_possible($_), qw(
    Object::Remote::Connector::Local
    Object::Remote::Connector::LocalSudo
    Object::Remote::Connector::SSH
    Object::Remote::Connector::UNIX
  ); 
}

sub conn_from_spec {
  my ($class, $spec, @args) = @_;
  foreach my $poss (do { our @Guess }) {
    if (my $conn = $poss->($spec, @args)) {
      return $conn;
    }
  }
  
  return undef;
}

sub new_from_spec {
  my ($class, $spec) = @_;
  return $spec if blessed $spec;
  my $conn = $class->conn_from_spec($spec); 
  
  die "Couldn't figure out what to do with ${spec}"
    unless defined $conn;
    
  return $conn->maybe::start::connect;  
}

sub remote_object {
  my ($self, @args) = @_;
  Object::Remote::Handle->new(
    connection => $self, @args
  )->proxy;
}

sub connect {
  my ($self, $to) = @_;
  Dlog_debug { "Creating connection to remote node '$to' for connection $_" } $self->_id;
  return await_future(
    $self->send_class_call(0, 'Object::Remote', connect => $to)
  );
}

sub remote_sub {
  my ($self, $sub) = @_;
  my ($pkg, $name) = $sub =~ m/^(.*)::([^:]+)$/;
  Dlog_debug { "Invoking remote sub '$sub' for connection $_" } $self->_id;
  return await_future($self->send_class_call(0, $pkg, can => $name));
}

sub send_class_call {
  my ($self, $ctx, @call) = @_;
  Dlog_trace { "Sending a class call for connection $_" } $self->_id;
  $self->send(call => class_call_handler => $ctx => call => @call);
}

sub register_class_call_handler {
  my ($self) = @_;
  $self->local_objects_by_id->{'class_call_handler'} ||= do {
    my $o = $self->new_class_call_handler;
    $self->_local_object_to_id($o);
    $o;
  };
}

sub new_class_call_handler {
  Object::Remote::CodeContainer->new(
    code => sub {
      my ($class, $method) = (shift, shift);
      use_module($class)->$method(@_);
    }
  );
}

sub register_remote {
  my ($self, $remote) = @_;
  Dlog_trace { my $i = $remote->id; "Registered a remote object with id of '$i' for connection $_" } $self->_id;
  weaken($self->remote_objects_by_id->{$remote->id} = $remote);
  return $remote;
}

sub send_free {
  my ($self, $id) = @_;
  Dlog_trace { "sending request to free object '$id' for connection $_" } $self->_id;
  delete $self->remote_objects_by_id->{$id};
  $self->_send([ free => $id ]);
}

sub send {
  my ($self, $type, @call) = @_;

  my $future = CPS::Future->new;
  my $remote = $self->remote_objects_by_id->{$call[0]};

  unshift @call, $type => $self->_local_object_to_id($future);

  my $outstanding = $self->outstanding_futures;
  $outstanding->{$future} = $future;
  $future->on_ready(sub {
    undef($remote);
    delete $outstanding->{$future}
  });

  $self->_send(\@call);

  return $future;
}

sub send_discard {
  my ($self, $type, @call) = @_;

  unshift @call, $type => 'NULL';

  $self->_send(\@call);
}

sub _send {
  my ($self, $to_send) = @_;
  my $fh = $self->send_to_fh;
  Dlog_trace { "Starting to serialize data in argument to _send for connection $_" } $self->_id;
  my $serialized = $self->_serialize($to_send)."\n";
  Dlog_trace { my $l = length($serialized); "serialization is completed; sending '$l' characters of serialized data to $_" } $fh;
  my $ret; 
  eval { 
    #TODO this should be converted over to a non-blocking ::WriteChannel class
    die "filehandle is not open" unless openhandle($fh);
    log_trace { "file handle has passed openhandle() test; printing to it" };
    $ret = print $fh $serialized;
    die "print was not successful: $!" unless defined $ret
  };
    
  if ($@) {
    Dlog_debug { "exception encountered when trying to write to file handle $_: $@" } $fh;
    my $error = $@; chomp($error);
    $self->on_close->done("could not write to file handle: $error") unless $self->on_close->is_ready;
    return; 
  }
      
  return $ret; 
}

sub _serialize {
  my ($self, $data) = @_;
  local our @New_Ids = (-1);
  return eval {
    my $flat = $self->_encode($self->_deobjectify($data));
    $flat;
  } || do {
    my $err = $@; # won't get here if the eval doesn't die
    # don't keep refs to new things
    delete @{$self->local_objects_by_id}{@New_Ids};
    die "Error serializing: $err";
  };
}

sub _local_object_to_id {
  my ($self, $object) = @_;
  my $id = refaddr($object);
  $self->local_objects_by_id->{$id} ||= do {
    push our(@New_Ids), $id if @New_Ids;
    $object;
  };
  return $id;
}

sub _deobjectify {
  my ($self, $data) = @_;
  if (blessed($data)) {
    if (
      $data->isa('Object::Remote::Proxy')
      and $data->{remote}->connection == $self
    ) {
      return +{ __local_object__ => $data->{remote}->id };
    } else {
      return +{ __remote_object__ => $self->_local_object_to_id($data) };
    }
  } elsif (my $ref = ref($data)) {
    if ($ref eq 'HASH') {
      my $tied_to = tied(%$data);
      if(defined($tied_to)) {
        return +{__remote_tied_hash__ => $self->_local_object_to_id($tied_to)}; 
      } else {
        return +{ map +($_ => $self->_deobjectify($data->{$_})), keys %$data };
      }
    } elsif ($ref eq 'ARRAY') {
      my $tied_to = tied(@$data);
      if (defined($tied_to)) {
        return +{__remote_tied_array__ => $self->_local_object_to_id($tied_to)}; 
      } else {
        return [ map $self->_deobjectify($_), @$data ];
      }
    } elsif ($ref eq 'CODE') {
      my $id = $self->_local_object_to_id(
                 Object::Remote::CodeContainer->new(code => $data)
               );
      return +{ __remote_code__ => $id };
    } elsif ($ref eq 'SCALAR') {
      return +{ __scalar_ref__ => $$data };
    } elsif ($ref eq 'GLOB') {
      return +{ __glob_ref__ => $self->_local_object_to_id(
        Object::Remote::GlobContainer->new(handle => $data)
      ) };
    } else {
      die "Can't collapse reftype $ref";
    }
  }
  return $data; # plain scalar
}

sub _receive {
  my ($self, $flat) = @_;
  Dlog_trace { my $l = length($flat); "Starting to deserialize $l characters of data for connection $_" } $self->_id;
  my ($type, @rest) = eval { @{$self->_deserialize($flat)} }
    or do { warn "Deserialize failed for ${flat}: $@"; return };
  Dlog_trace { "deserialization complete for connection $_" } $self->_id;
  eval { $self->${\"receive_${type}"}(@rest); 1 }
    or do { warn "Receive failed for ${flat}: $@"; return };
  return;
}

sub receive_free {
  my ($self, $id) = @_;
  Dlog_trace { "got a receive_free for object '$id' for connection $_" } $self->_id;
  delete $self->local_objects_by_id->{$id}
    or warn "Free: no such object $id";
  return;
}

sub receive_call {
  my ($self, $future_id, $id, @rest) = @_;
  Dlog_trace { "got a receive_call for object '$id' for connection $_" } $self->_id;
  my $future = $self->_id_to_remote_object($future_id);
  $future->{method} = 'call_discard_free';
  my $local = $self->local_objects_by_id->{$id}
    or do { $future->fail("No such object $id"); return };
  $self->_invoke($future, $local, @rest);
}

sub receive_call_free {
  my ($self, $future, $id, @rest) = @_;
  Dlog_trace { "got a receive_call_free for object '$id' for connection $_" } $self->_id;
  $self->receive_call($future, $id, undef, @rest);
  $self->receive_free($id);
}

sub _invoke {
  my ($self, $future, $local, $ctx, $method, @args) = @_;
  Dlog_trace { "got _invoke for a method named '$method' for connection $_" } $self->_id;
  if ($method =~ /^start::/) {
    my $f = $local->$method(@args);
    $f->on_done(sub { undef($f); $future->done(@_) });
    return unless $f;
    $f->on_fail(sub { undef($f); $future->fail(@_) });
    return;
  }
  my $do = sub { $local->$method(@args) };
  eval {
    $future->done(
      defined($ctx)
        ? ($ctx ? $do->() : scalar($do->()))
        : do { $do->(); () }
    );
    1;
  } or do { $future->fail($@); return; };
  return;
}

1;

=head1 NAME

Object::Remote::Connection - An underlying connection for L<Object::Remote>

=head1 LAME

Shipping prioritised over writing this part up. Blame mst.

=cut
