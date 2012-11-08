package Object::Remote::Logging;

use Moo;
use Scalar::Util qw(blessed);
use Object::Remote::Logging::Logger;
use Exporter::Declare;
use Carp qw(carp croak);

extends 'Log::Contextual';

exports(qw( ____ router arg_levels ));
#exception log - log a message then die with that message
export_tag elog => ('____');
#fatal log - log a message then call exit(1)
export_tag flog => ('____');

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

sub before_import {
   my ($class, $importer, $spec) = @_;
   my $router = $class->router;

   $class->SUPER::before_import($importer, $spec);

   my @levels = @{$class->arg_levels($spec->config->{levels})};
   for my $level (@levels) {
      if ($spec->config->{elog}) {
         $spec->add_export("&Elog_$level", sub (&) {
            my ($code, @args) = @_;
            $router->handle_log_request({
               controller => $class,
               package => scalar(caller),
               caller_level => 1,
               level => $level,
            }, $code);
            #TODO this should get fed into a logger so it can be formatted
            croak $code->();
         });
      }
      if ($spec->config->{flog}) {
         #TODO that prototype isn't right
         $spec->add_export("&Flog_$level", sub (&@) {
            my ($code, $exit_value) = @_;
            $exit_value = 1 unless defined $exit_value;
            $router->handle_log_request({
               controller => $class,
               package => scalar(caller),
               caller_level => 1,
               level => $level,
            }, $code);
            #TODO this should get fed into a logger so it can be formatted
            carp $code->();
            exit($exit_value);
         });
      }
   }
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

