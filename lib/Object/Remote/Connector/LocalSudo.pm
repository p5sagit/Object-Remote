package Object::Remote::Connector::LocalSudo;

use Symbol qw(gensym);
use IPC::Open3;
use Moo;

extends 'Object::Remote::Connector::Local';

has password_callback => (is => 'ro');

sub _sudo_perl_command {
  my ($self, $stderr_fdno, $target_user) = @_;
  return
    'sudo', '-S', '-u', $target_user, '-p', "[sudo] password please\n",
    'perl', '-MPOSIX=dup2',
            '-e', 'print STDERR "GO\n"; dup2(shift(@ARGV), 2); exec(@ARGV);',
    $stderr_fdno, $self->_perl_command($target_user);
}

sub _start_perl {
  my $self = shift;
  open my $stderr_dup, '>&', \*STDERR or die "Couldn't dup STDERR: $!";
  my $sudo_stderr = gensym;
  my $pid = open3(
    my $foreign_stdin,
    my $foreign_stdout,
    $sudo_stderr,
    $self->_sudo_perl_command(fileno($stderr_dup), @_)
  ) or die "open3 failed: $!";
  chomp(my $line = <$sudo_stderr>);
  if ($line eq "GO") {
    # started already, we're good
  } elsif ($line =~ /\[sudo\]/) {
    my $cb = $self->password_callback;
    die "sudo sent ${line} but we have no password callback"
      unless $cb;
    print $foreign_stdin $cb->($line, @_), "\n";
    chomp($line = <$sudo_stderr>);
    die "sent password but next line was ${line}"
      unless $line eq "GO";
  } else {
    die "Got inexplicable line ${line} trying to sudo";
  };
  return ($foreign_stdin, $foreign_stdout, $pid);
};

no warnings 'once';

push @Object::Remote::Connection::Guess, sub {
  for ($_[0]) {
    # username followed by @
    if (defined and !ref and /^ ([^\@]*?) \@ $/x) {
      return __PACKAGE__->new->connect($1);
    }
  }
  return;
};

1;
