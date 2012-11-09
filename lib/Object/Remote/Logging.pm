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
            #don't let it going wrong stop us from calling exit()
            eval { carp $code->() };
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
__END__

=head1 NAME

Object::Remote::Logging - Logging subsystem for Object::Remote

=head1 SYNOPSIS

  use Object::Remote::Logging qw( :log :dlog :elog :flog arg_levels router );
  
  @levels = qw( trace debug verbose info warn error fatal );
  @levels = arg_levels(); #same result
  
  $ENV{OBJECT_REMOTE_LOG_LEVEL} = 'trace'; #or other level name
  $ENV{OBJECT_REMOTE_LOG_FORMAT} = '%l %t: %p::%m %s'; #and more
  $ENV{OBJECT_REMOTE_LOG_FORWARDING} = 0 || 1; #default 0
  $ENV{OBJECT_REMOTE_LOG_SELECTIONS} = 'Object::Remote::Logging Some::Other::Subclass';
  
  log_info { 'Trace log event' };
  Dlog_verbose { "Debug event with Data::Dumper::Concise: $_" } { foo => 'bar' };
  Elog_error { 'Error event that calls die() with this string' };
  Flog_fatal { 'Fatal event calls warn() then exit()' } 1;

=head1 DESCRIPTION

This is the logging framework for Object::Remote implemented as a subclass of
L<Log::Contextual> with a slightly incompatible API. This system allows 
developers using Object::Remote and end users of that software to control
Object::Remote logging so operation can be tracked if needed. This is also
the API used to generate log messages inside the Object::Remote source code.

The rest of the logging system comes from L<Object::Remote::Logging::Logger>
which implements log rendering and output and L<Object::Remote::Logging::Router>
which delivers log events to the loggers.

=head1 EXPORTABLE SUBROUTINES

=over 4

=item arg_levels

Returns an array reference that contains the ordered list of level names
with the lowest log level first and the highest log level last.

=item router

Returns the instance of L<Object::Remote::Logging::Router> that is in use. The router
instance is used in combination with L<Object::Remote::Logging::Logger> objects to
select then render and output log messages.

=item log_<level> and Dlog_<level>

These methods come direct from L<Log::Contextual>; see that documentation for a 
complete reference. For each of the log level names there are subroutines with the log_
and Dlog_ prefix that will generate the log message. The first argument is a code block
that returns the log message contents and the optional further arguments are both passed
to the block as the argument list and returned from the log method as a list.

  log_trace { "A fine log message $_[0] " } 'if I do say so myself';
  $hashref = Dlog_trace { "Very handy: $_" } { foo => 'bar' };

=item logS_<level> and DlogS_<level>

Works just like log_ and Dlog_ except returns only the first argument as a scalar value.

  my $beverage = log_info { "Customer ordered $_[0]" } 'Coffee';

=item Elog_<level>

Log an event and then generate an exception by calling die() with the log message.

  Elog_error { "Could not open file: $!" };

=item Flog_<level>

Log the event, generate a warning with the log message, then call exit(). The exit
value will default to 1 or can be specified as an argument.

  Flog_fatal { 'Could not lock resource' } 3;

=back

=head1 LEVEL NAMES

Object::Remote uses an ordered list of log level names with the minimum level
first and the maximum level last. The list of level names can be accessed via
the arg_levels method which is exportable to the consumer of this class. The log
level names are:

=over 4

=item trace

As much information about operation as possible including multiple line dumps of
large content. Tripple verbose operation (-v -v -v).

=item debug

Messages about operations that could hang as well as internal state changes, 
results from method invocations, and information useful when looking for faults.
Double verbose operation (-v -v).

=item verbose

Additional optional messages to the user that can be enabled at their will. Single
verbose operation (-v).

=item info

Messages from normal operation that are intended to be displayed to the end
user if quiet operation is not indicated and more verbose operation is not
in effect.

=item warn

Something wasn't supposed to happen but did. Operation was not impacted but
otherwise the event is noteworthy. Single quiet operation (-q).

=item error

Something went wrong. Operation of the system may continue but some operation
has most definitely failed. Double quiet operation (-q -q).

=item fatal

Something went wrong and recovery is not possible. The system should stop operating
as soon as possible. Tripple quiet operation (-q -q -q).

=back

=head1 ENVIRONMENT

=over 4

=item OBJECT_REMOTE_LOG_LEVEL

By default Object::Remote will generate log events but messages will not be
output to STDERR. If there is a defined value for this variable then logs will
be sent to STDERR if they are at this level or higher.

=item OBJECT_REMOTE_LOG_FORMAT

If logging output is enabled and this value is defined then the logger will
use this format string instead of the default '[%l %r] %s'; See 
L<Object::Remote::Logging::Logger> for documentation on the format string.

=item OBJECT_REMOTE_LOG_SELECTIONS

By default Object::Remote log output will only be enabled for messages generated inside
Object::Remote packages. If logs should be generated for other log messages instead of just
Object::Remote messages set this variable to the names of any Object::Remote::Logging subclass or 
Object::Remote::Logging itself seperated by a space. To output all logs generated set the value
to *.

=item OBJECT_REMOTE_LOG_FORWARDING

Object::Remote can forward log events from the remote Perl interpreter to the local Perl
interpreter in a transparent way. Currently this feature is disabled by default but
that will change Really Soon Now(TM); to enable it set the variable to '1'.

=back

