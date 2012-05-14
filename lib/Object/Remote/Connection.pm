package Object::Remote::Connection;

use CPS::Future;
use Object::Remote::Null;
use Object::Remote;
use IO::Handle;
use Module::Runtime qw(use_module);
use Scalar::Util qw(weaken blessed refaddr);
use JSON::PP qw(encode_json);
use Moo;

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

has _receive_data_buffer => (is => 'ro', default => sub { my $x = ''; \$x });

has local_objects_by_id => (is => 'ro', default => sub { {} });

has remote_objects_by_id => (
  is => 'ro', default => sub { { NULL => bless({}, 'Object::Remote::Null') } }
);

has _json => (
  is => 'lazy',
  handles => {
    _deserialize => 'decode',
    _encode => 'encode',
  },
);

sub _build__json {
  weaken(my $self = shift);
  my $remotes = $self->remote_objects_by_id;
  JSON::PP->new->filter_json_single_key_object(
    __remote_object__ => sub {
      my $id = shift;
      (
        $remotes->{$id}
        or Object::Remote->new(connection => $self, id => $id)
      )->proxy;
    }
  );
}

sub register_remote {
  my ($self, $remote) = @_;
  weaken($self->remote_objects_by_id->{$remote->id} = $remote);
  return $remote;
}

sub send_free {
  my ($self, $id) = @_;
  delete $self->remote_objects_by_id->{$id};
  $self->_send([ free => $id ]);
}

sub send {
  my ($self, $type, @call) = @_;

  unshift @call, $type => my $future = CPS::Future->new;

  $self->_send(\@call);

  return $future;
}

sub send_discard {
  my ($self, $type, @call) = @_;

  unshift @call, $type => { __remote_object => 'NULL' };

  $self->_send(\@call);
}

sub _send {
  my ($self, $to_send) = @_;

  print { $self->send_to_fh } $self->_serialize($to_send)."\n";
}

sub _serialize {
  my ($self, $data) = @_;
  local our @New_Ids;
  return eval {
    $self->_encode($self->_deobjectify($data))
  } or do {
    my $err = $@; # won't get here if the eval doesn't die
    # don't keep refs to new things
    delete @{$self->local_objects_by_id}{@New_Ids};
    die "Error serializing: $err";
  };
}

sub _deobjectify {
  my ($self, $data) = @_;
  if (blessed($data)) {
    my $id = refaddr($data);
    $self->local_objects_by_id->{$id} ||= do {
      push our(@New_Ids), $id;
      $data;
    };
    return +{ __remote_object__ => $id };
  } elsif (my $ref = ref($data)) {
    if ($ref eq 'HASH') {
      return +{ map +($_ => $self->_deobjectify($data->{$_})), keys %$data };
    } elsif ($ref eq 'ARRAY') {
      return [ map $self->_deobjectify($_), @$data ];
    } else {
      die "Can't collapse reftype $ref";
    }
  }
  return $data; # plain scalar
}

sub _receive_data_from {
  my ($self, $fh) = @_;
  my $rb = $self->_receive_data_buffer;
  if (sysread($fh, $$rb, 1024, length($$rb)) > 0) {
    while ($$rb =~ s/^(.*)\n//) {
      $self->_receive($1);
    }
  }
}

sub _receive {
  my ($self, $data) = @_;
  my ($type, @rest) = eval { @{$self->_deserialize($data)} }
    or do { warn "Deserialize failed for ${data}: $@"; return };
  eval { $self->${\"receive_${type}"}(@rest); 1 }
    or do { warn "Receive failed for ${data}: $@"; return };
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
  my $local = $self->local_objects_by_id->{$id}
    or do { $future->fail("No such object $id"); return };
  $self->_invoke($future, $local, @rest);
}

sub receive_class_call {
  my ($self, $future, $class, @rest) = @_;
  eval { use_module($class) }
    or do { $future->fail("Error loading ${class}: $@"); return };
  $self->_invoke($future, $class, @rest);
}

sub _invoke {
  my ($self, $future, $local, $method, @args) = @_;
  eval { $future->done($local->$method(@args)); 1 }
    or do { $future->fail($@); return; };
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