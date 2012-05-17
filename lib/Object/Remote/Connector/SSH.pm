package Object::Remote::Connector::SSH;

use Object::Remote::FatNode;
use Object::Remote::ModuleSender;
use IPC::Open2;
use Moo;

with 'Object::Remote::Role::Connector';

sub _open2_for {
  my $self = shift;
  my $pid = open2(my $ssh_stdout, my $ssh_stdin, 'ssh', $_[0], 'perl', '-')
    or die "Failed to start ssh connection: $!";;
  print $ssh_stdin $Object::Remote::FatNode::DATA, "__END__\n";
  return ($ssh_stdin, $ssh_stdout, $pid);
}

around connect => sub {
  my ($orig, $self) = (shift, shift);
  my $conn = $self->$orig(@_);
  Object::Remote->new(
    connection => $conn,
    class => 'Object::Remote::ModuleLoader',
    args => { module_sender => Object::Remote::ModuleSender->new }
  )->disarm_free;
  return $conn;
};

sub _ssh_object_for {
  my ($self, $on) = @_;
  $self->ssh_masters->{$on} ||= Net::OpenSSH->new($on);
}

push @Object::Remote::Connection::Guess, sub { 
  for ($_[0]) {
    # 0-9 a-z _ - first char, those or . subsequent - hostnamish
    if (defined and !ref and /^(?:.*?\@)?[\w\-][\w\-\.]*/) {
      return __PACKAGE__->new->connect($_[0]);
    }
  }
  return;
};

1;
