package Object::Remote::Role::Connector::PerlInterpreter;

use IPC::Open2;
use IO::Handle;
use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Scalar::Util qw(blessed);
use Moo::Role;

with 'Object::Remote::Role::Connector';

has module_sender => (is => 'lazy');

sub _build_module_sender {
  my ($hook) =
    grep {blessed($_) && $_->isa('Object::Remote::ModuleLoader::Hook') }
      @INC;
  return $hook ? $hook->sender : Object::Remote::ModuleSender->new;
}

around connect => sub {
  my ($orig, $self) = (shift, shift);
  my $conn = $self->$orig(@_);
  Object::Remote::Handle->new(
    connection => $conn,
    class => 'Object::Remote::ModuleLoader',
    args => { module_sender => $self->module_sender }
  )->disarm_free;
  return $conn;
};

sub _perl_command { 'perl', '-' }

sub _start_perl {
  my $self = shift;
  my $pid = open2(
    my $foreign_stdout,
    my $foreign_stdin,
    $self->_perl_command(@_),
  ) or die "Failed to run perl at '$_[0]': $!";
  return ($foreign_stdin, $foreign_stdout, $pid);
}

sub _open2_for {
  my $self = shift;
  my ($foreign_stdin, $foreign_stdout, $pid) = $self->_start_perl(@_);
  $foreign_stdin->autoflush(1);
  print $foreign_stdin 'BEGIN { $ENV{OBJECT_REMOTE_DEBUG} = 1 }'."\n"
    if $ENV{OBJECT_REMOTE_DEBUG};
  print $foreign_stdin $self->fatnode_text
    or die "Failed to send fatpacked data to new node on '$_[0]': $!";
  return ($foreign_stdin, $foreign_stdout, $pid);
}

sub fatnode_text {
  my ($self) = @_;
  require Object::Remote::FatNode;
  my $text = '';
  $text .= 'BEGIN { $ENV{OBJECT_REMOTE_DEBUG} = 1 }'."\n"
    if $ENV{OBJECT_REMOTE_DEBUG};
  $text .= <<'END';
$INC{'Object/Remote/FatNode.pm'} = __FILE__;
$Object::Remote::FatNode::DATA = <<'ENDFAT';
END
  $text .= $Object::Remote::FatNode::DATA;
  $text .= "ENDFAT\n";
  $text .= <<'END';
eval $Object::Remote::FatNode::DATA;
END
  $text .= "__END__\n";
  return $text;
}

1;
