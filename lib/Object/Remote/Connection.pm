package Object::Remote::Connection;

use Object::Remote::Future;
use Object::Remote::Null;
use Object::Remote::Handle;
use Object::Remote::CodeContainer;
use Object::Remote;
use IO::Handle;
use Module::Runtime qw(use_module);
use Scalar::Util qw(weaken blessed refaddr);
use JSON::PP qw(encode_json);
use Moo;

our $DEBUG = !!$ENV{OBJECT_REMOTE_DEBUG};

has send_to_fh => (
  is => 'ro', required => 1,
  trigger => sub { $_[1]->autoflush(1) },
);

has receive_from_fh => (
  is => 'ro', required => 1,
  trigger => sub {
    my ($self, $fh) = @_;
    weaken($self);
    Object::Remote->current_loop
                  ->watch_io(
                      handle => $fh,
                      on_read_ready => sub { $self->_receive_data_from($fh) }
                    );
  },
);

has on_close => (is => 'rw', default => sub { CPS::Future->new });

has child_pid => (is => 'ro');

has ready_future => (is => 'lazy');

sub _build_ready_future { CPS::Future->new }

has _receive_data_buffer => (is => 'ro', default => sub { my $x = ''; \$x });

has local_objects_by_id => (is => 'ro', default => sub { {} });

has remote_objects_by_id => (is => 'ro', default => sub { {} });

has outstanding_futures => (is => 'ro', default => sub { {} });

has _json => (
  is => 'lazy',
  handles => {
    _deserialize => 'decode',
    _encode => 'encode',
  },
);

sub _id_to_remote_object {
  my ($self, $id) = @_;
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
  );
}

BEGIN {
  unshift our @Guess, sub { blessed($_[0]) ? $_[0] : undef };
  eval { require Object::Remote::Connector::Local };
  eval { require Object::Remote::Connector::LocalSudo };
  eval { require Object::Remote::Connector::SSH };
  eval { require Object::Remote::Connector::UNIX };
}

sub new_from_spec {
  my ($class, $spec) = @_;
  return $spec if blessed $spec;
  foreach my $poss (do { our @Guess }) {
    if (my $obj = $poss->($spec)) { return $obj }
  }
  die "Couldn't figure out what to do with ${spec}";
}

sub new_remote {
  my ($self, @args) = @_;
  Object::Remote::Handle->new(
    connection => $self, @args
  )->proxy;
}

sub connect {
  my ($self, $to) = @_;
  return await_future($self->send(
    class_call => 'Object::Remote', 0, connect => $to
  ));
}

sub get_remote_sub {
  my ($self, $sub) = @_;
  my ($pkg, $name) = $sub =~ m/^(.*)::([^:]+)$/;
  return await_future($self->send(class_call => $pkg, 0, can => $name));
}

sub register_remote {
  my ($self, $remote) = @_;
  weaken($self->remote_objects_by_id->{$remote->id} = $remote);
  return $remote;
}

sub await_ready {
  my ($self) = @_;
  await_future($self->ready_future);
}

sub send_free {
  my ($self, $id) = @_;
  delete $self->remote_objects_by_id->{$id};
  $self->_send([ free => $id ]);
}

sub send {
  my ($self, $type, @call) = @_;

  unshift @call, $type => my $future = CPS::Future->new;

  my $outstanding = $self->outstanding_futures;
  $outstanding->{$future} = $future;
  $future->on_ready(sub { delete $outstanding->{$future} });

  $self->_send(\@call);

  return $future;
}

sub send_discard {
  my ($self, $type, @call) = @_;

  unshift @call, $type => { __remote_object__ => 'NULL' };

  $self->_send(\@call);
}

sub _send {
  my ($self, $to_send) = @_;

  $self->await_ready;

  print { $self->send_to_fh } $self->_serialize($to_send)."\n";
}

sub _serialize {
  my ($self, $data) = @_;
  local our @New_Ids;
  return eval {
    my $flat = $self->_encode($self->_deobjectify($data));
    warn "$$ >>> ${flat}\n" if $DEBUG;
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
    push our(@New_Ids), $id;
    $object;
  };
  return $id;
}

sub _deobjectify {
  my ($self, $data) = @_;
  if (blessed($data)) {
    return +{ __remote_object__ => $self->_local_object_to_id($data) };
  } elsif (my $ref = ref($data)) {
    if ($ref eq 'HASH') {
      return +{ map +($_ => $self->_deobjectify($data->{$_})), keys %$data };
    } elsif ($ref eq 'ARRAY') {
      return [ map $self->_deobjectify($_), @$data ];
    } elsif ($ref eq 'CODE') {
      my $id = $self->_local_object_to_id(
                 Object::Remote::CodeContainer->new(code => $data)
               );
      return +{ __remote_code__ => $id };
    } else {
      die "Can't collapse reftype $ref";
    }
  }
  return $data; # plain scalar
}

sub _receive_data_from {
  my ($self, $fh) = @_;
  my $rb = $self->_receive_data_buffer;
  my $ready = $self->ready_future->is_ready;
  my $len = sysread($fh, $$rb, 1024, length($$rb));
  my $err = defined($len) ? undef : ": $!";
  if (defined($len) and $len > 0) {
    while ($$rb =~ s/^(.*)\n//) {
      if ($ready) {
        $self->_receive($1);
      } else {
        my $line = $1;
        die "New remote container did not send Shere - got ${line}"
          unless $line eq "Shere";
        $self->ready_future->done;
      }
    }
  } else {
    Object::Remote->current_loop
                  ->unwatch_io(
                      handle => $self->receive_from_fh,
                      on_read_ready => 1
                    );
    my $outstanding = $self->outstanding_futures;
    $_->fail("Connection lost${err}") for values %$outstanding;
    %$outstanding = ();
    $self->on_close->done();
  }
}

sub _receive {
  my ($self, $flat) = @_;
  warn "$$ <<< $flat\n" if $DEBUG;
  my ($type, @rest) = eval { @{$self->_deserialize($flat)} }
    or do { warn "Deserialize failed for ${flat}: $@"; return };
  eval { $self->${\"receive_${type}"}(@rest); 1 }
    or do { warn "Receive failed for ${flat}: $@"; return };
  return;
}

sub receive_free {
  my ($self, $id) = @_;
  delete $self->local_objects_by_id->{$id}
    or warn "Free: no such object $id";
  return;
}

sub receive_call {
  my ($self, $future, $id, @rest) = @_;
  $future->{method} = 'call_discard_free';
  my $local = $self->local_objects_by_id->{$id}
    or do { $future->fail("No such object $id"); return };
  $self->_invoke($future, $local, @rest);
}

sub receive_call_free {
  my ($self, $future, $id, @rest) = @_;
  $self->receive_call($future, $id, undef, @rest);
  $self->receive_free($id);
}

sub receive_class_call {
  my ($self, $future, $class, @rest) = @_;
  $future->{method} = 'call_discard_free';
  eval { use_module($class) }
    or do { $future->fail("Error loading ${class}: $@"); return };
  $self->_invoke($future, $class, @rest);
}

sub _invoke {
  my ($self, $future, $local, $ctx, $method, @args) = @_;
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

sub DEMOLISH {
  my ($self, $gd) = @_;
  return if $gd;
  Object::Remote->current_loop
                ->unwatch_io(
                    handle => $self->receive_from_fh,
                    on_read_ready => 1
                  );
}

1;
