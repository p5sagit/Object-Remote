package Object::Remote::Connector::Local;

use IPC::Open2;
use Object::Remote::Connection;
use Moo;

sub connect {
  # XXX bin/ is wrong but meh, fix later
  my $pid = open2(my $its_stdout, my $its_stdin, 'bin/object-remote-node')
    or die "Couldn't start local node: $!";
  Object::Remote::Connection->new(
    send_to_fh => $its_stdin,
    receive_from_fh => $its_stdout,
    child_pid => $pid
  );
}

1;
