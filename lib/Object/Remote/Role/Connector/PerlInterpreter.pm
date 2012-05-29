package Object::Remote::Role::Connector::PerlInterpreter;

use IPC::Open2;
use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Object::Remote::FatNode;
use Moo::Role;

with 'Object::Remote::Role::Connector';

around connect => sub {
  my ($orig, $self) = (shift, shift);
  my $conn = $self->$orig(@_);
  Object::Remote::Handle->new(
    connection => $conn,
    class => 'Object::Remote::ModuleLoader',
    args => { module_sender => Object::Remote::ModuleSender->new }
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
  print $foreign_stdin $Object::Remote::FatNode::DATA, "__END__\n";
  return ($foreign_stdin, $foreign_stdout, $pid);
}

1;
