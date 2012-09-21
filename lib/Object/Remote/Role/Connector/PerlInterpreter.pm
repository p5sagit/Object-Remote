package Object::Remote::Role::Connector::PerlInterpreter;

use IPC::Open2;
use IPC::Open3; 
use IO::Handle;
use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Object::Remote::Future;
use Object::Remote::Logging qw( :log :dlog );
use Scalar::Util qw(blessed);
use Moo::Role;

with 'Object::Remote::Role::Connector';

has module_sender => (is => 'lazy');
#if no child_stderr file handle is specified then stderr
#of the child will be connected to stderr of the parent
has stderr => ( is => 'rw', default => sub { \*STDERR } );

sub _build_module_sender {
  my ($hook) =
    grep {blessed($_) && $_->isa('Object::Remote::ModuleLoader::Hook') }
      @INC;
  return $hook ? $hook->sender : Object::Remote::ModuleSender->new;
}

has perl_command => (is => 'lazy');

#TODO convert nice value into optional feature enabled by
#setting value of attribute
#ulimit of ~500 megs of v-ram
#TODO only works with ssh with quotes but only works locally
#with out quotes
#sub _build_perl_command { [ 'sh', '-c', '"ulimit -v 80000; nice -n 15 perl -"' ] }
sub _build_perl_command { [ 'sh', '-c', '"ulimit -v 500000; nice -n 15 perl -"' ] }
#sub _build_perl_command { [ 'perl', '-' ] }

around connect => sub {
  my ($orig, $self) = (shift, shift);
  my $f = $self->$start::start($orig => @_);
  return future {
    $f->on_done(sub {
      my ($conn) = $f->get;
      my $sub = $conn->remote_sub('Object::Remote::Logging::init_logging_forwarding');
      $sub->('Object::Remote::Logging', Object::Remote::Logging->arg_router);
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

sub final_perl_command { shift->perl_command }

sub _start_perl {
  my $self = shift;
  my $given_stderr = $self->stderr;
  my $foreign_stderr;
 
  Dlog_debug { "invoking connection to perl interpreter using command line: $_" } @{$self->final_perl_command};
  
  use Symbol; 
  
  if (defined($given_stderr)) {
      $foreign_stderr = gensym();
  } else {
      $foreign_stderr = ">&STDERR";
  }
  
  my $pid = open3(
    my $foreign_stdin,
    my $foreign_stdout,
    $foreign_stderr,
    @{$self->final_perl_command},
  ) or die "Failed to run perl at '$_[0]': $!";
  
  if (defined($given_stderr)) {   
      log_warn { "using experimental cat for child stderr" };
        
      #TODO refactor if this solves the problem
      Object::Remote->current_loop
                    ->watch_io(
                        handle => $foreign_stderr,
                        on_read_ready => sub {
                          my $buf = ''; 
                          my $len = sysread($foreign_stderr, $buf, 32768);
                          if (!defined($len) or $len == 0) {
                            log_trace { "Got EOF or error on child stderr, removing from watcher" };
                            $self->stderr(undef);
                            Object::Remote->current_loop
                                          ->unwatch_io(
                                              handle => $foreign_stderr,
                                              on_read_ready => 1
                                            );
                          } else {
                              Dlog_trace { "got $len characters of stderr data for connection" };
                              print $given_stderr $buf or die "could not send stderr data: $!";
                          }
                         }
                      );     
  }
      
  #TODO open2() dupes the child stderr into the calling
  #process stderr which means if this process exits the
  #child is still attached to the shell - using open3()
  #and having the run loop manage the stderr means this
  #won't happen BUT if the run loop just sends the remote
  #stderr data to the local stderr the logs will interleave
  #for sure - a simple test would be to use open3() and just
  #close the remote stderr and see what happens - a longer
  #term solution would be for Object::Remote to offer a feature
  #where the user of a connection species a destination for output
  #either a file name or their own file handle and the node output
  #is dumped to it 
#  my $pid = open2(
#    my $foreign_stdout,
#    my $foreign_stdin,
#    @{$self->final_perl_command},
#  ) or die "Failed to run perl at '$_[0]': $!";

  Dlog_trace { "Connection to remote side successful; remote stdin and stdout: $_" } [ $foreign_stdin, $foreign_stdout ];
  return ($foreign_stdin, $foreign_stdout, $pid);
}

#TODO open2() forks off a child and I have not been able to locate
#a mechanism for reaping dead children so they don't become zombies
#CONFIRMED there is no reaping of children being done, find a safe
#way to do it
sub _open2_for {
  my $self = shift;
  my ($foreign_stdin, $foreign_stdout, $pid) = $self->_start_perl(@_);
  my $to_send = $self->fatnode_text;
  log_debug { my $len = length($to_send); "Sending contents of fat node to remote node; size is '$len' characters"  };
  Object::Remote->current_loop
                ->watch_io(
                    handle => $foreign_stdin,
                    on_write_ready => sub {
                      my $len = syswrite($foreign_stdin, $to_send, 32768);
                      if (defined $len) {
                        substr($to_send, 0, $len) = '';
                      }
                      # if the stdin went away, we'll never get Shere
                      # so it's not a big deal to simply give up on !defined
                      if (!defined($len) or 0 == length($to_send)) {
                        log_trace { "Got EOF or error when writing fatnode data to filehandle, unwatching it" };
                        Object::Remote->current_loop
                                      ->unwatch_io(
                                          handle => $foreign_stdin,
                                          on_write_ready => 1
                                        );
                      } else {
                          log_trace { "Sent $len bytes of fatnode data to remote side" };
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
die $@ if $@;
END
  $text .= "__END__\n";
  return $text;
}

1;
