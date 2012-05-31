package Object::Remote::Role::Connector::PerlInterpreter;

use IPC::Open2;
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

sub _open2_for {
  my $self = shift;
  my $pid = open2(
    my $foreign_stdout,
    my $foreign_stdin,
    $self->_perl_command(@_),
  ) or die "Failed to run perl at '$_[0]': $!";
  require Object::Remote::FatNode;
  print $foreign_stdin $Object::Remote::FatNode::DATA, "__END__\n"
    or die "Failed to send fatpacked data to new node on '$_[0]': $!";
  return ($foreign_stdin, $foreign_stdout, $pid);
}

1;
