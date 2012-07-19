package Object::Remote::Role::Connector::PerlInterpreter;

use IPC::Open2;
use IO::Handle;
use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Object::Remote::Future;
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
  my $f = $self->$start::start($orig => @_);
  return future {
    $f->on_done(sub {
      my ($conn) = $f->get;
      Object::Remote::Handle->new(
        connection => $conn,
        class => 'Object::Remote::ModuleLoader',
        args => { module_sender => $self->module_sender }
      )->disarm_free;
      require Object::Remote::Prompt;
      Object::Remote::Prompt::maybe_set_prompt_command_on($conn);
    });
    $f;
  } 2;
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
  my $to_send = $self->fatnode_text;
  Object::Remote->current_loop
                ->watch_io(
                    handle => $foreign_stdin,
                    on_write_ready => sub {
                      my $len = syswrite($foreign_stdin, $to_send, 4096);
                      if (defined $len) {
                        substr($to_send, 0, $len) = '';
                      }
                      # if the stdin went away, we'll never get Shere
                      # so it's not a big deal to simply give up on !defined
                      if (!defined($len) or 0 == length($to_send)) {
                        Object::Remote->current_loop
                                      ->unwatch_io(
                                          handle => $foreign_stdin,
                                          on_write_ready => 1
                                        );
                      }
                    }
                  );
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
  $text .= do { no warnings 'once'; $Object::Remote::FatNode::DATA };
  $text .= "ENDFAT\n";
  $text .= <<'END';
eval $Object::Remote::FatNode::DATA;
END
  $text .= "__END__\n";
  return $text;
}

1;
