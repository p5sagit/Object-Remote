package Object::Remote::Logging;

use Moo;
use Scalar::Util qw(blessed);
use Object::Remote::Logging::Logger;
use Exporter::Declare;

extends 'Log::Contextual';

exports(qw( router arg_levels ));

sub router {
  our $Router_Instance ||= do {
    require Object::Remote::Logging::Router;
    Object::Remote::Logging::Router->new;
  }
}

#log level descriptions
#info - standard log level - normal program output for the end user
#warn - output for program that is executing quietly
#error - output for program that is running more quietly
#fatal - it is not possible to continue execution; this level is as quiet as is possible
#verbose - output for program executing verbosely (-v)
#debug - output for program running more verbosely (-v -v)
#trace - output for program running extremely verbosely (-v -v -v)
sub arg_levels {
  #the order of the log levels is significant with the
  #most verbose level being first in the list and the
  #most quiet as the last item
  return [qw( trace debug verbose info warn error fatal )];
}

#this is invoked on all nodes
sub init_logging {
  my $level = $ENV{OBJECT_REMOTE_LOG_LEVEL};
  my $format = $ENV{OBJECT_REMOTE_LOG_FORMAT};
  #TODO allow the selections value to be * so it selects everything
  my $selections = $ENV{OBJECT_REMOTE_LOG_SELECTIONS};
  my %controller_should_log;
  
  return unless defined $level;
  $format = "[%l %r] %s" unless defined $format;
  $selections = __PACKAGE__ unless defined $selections;
  %controller_should_log = map { $_ => 1 } split(' ', $selections);
  
  my $logger = Object::Remote::Logging::Logger->new(
    min_level => lc($level), format => $format,
    level_names => Object::Remote::Logging::arg_levels(),
  );

  router()->connect(sub { 
    my $controller = $_[1]->{controller};
    return unless  $controller_should_log{'*'} || $controller_should_log{$controller};
    #skip things from remote hosts because they log to STDERR
    #when OBJECT_REMOTE_LOG_LEVEL is in effect
    return if $_[1]->{remote}->{connection_id};
    $logger
  });
}

#this is invoked by the controlling node
#on the remote nodes
sub init_logging_forwarding {
  my ($self, %controller_info) = @_;
  
  router()->_remote_metadata({ connection_id => $controller_info{connection_id} });
  router()->_forward_destination($controller_info{router}) if $ENV{OBJECT_REMOTE_LOG_FORWARDING};
}

1;

