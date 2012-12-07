package Object::Remote::Logging;

use Moo;
use Scalar::Util qw(blessed);
use Object::Remote::Logging::Logger;
use Exporter::Declare;
use Carp qw(carp croak);

extends 'Log::Contextual';

exports(qw( ____ router arg_levels ));

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
   our $DID_INIT;

   unless($DID_INIT) {
     $DID_INIT = 1;
     init_logging();
   }
      
   $class->SUPER::before_import($importer, $spec);
}

sub _parse_selections {
  my ($selections_string) = @_;
  my %log_ok;
    
  #example string:
  #"  * -Object::Remote::Logging    Foo::Bar::Baz   "
  foreach(split(/\s+/, $selections_string)) {
    next if $_ eq '';
    if ($_ eq '*') {
      $log_ok{$_} = 1;
    } elsif (s/^-//) {
      $log_ok{$_} = 0;
    } else {
      $log_ok{$_} = 1;
    }
  }
    
  return %log_ok;
}

#this is invoked on all nodes
sub init_logging {
  my $level = $ENV{OBJECT_REMOTE_LOG_LEVEL};
  my $format = $ENV{OBJECT_REMOTE_LOG_FORMAT};
  my $selections = $ENV{OBJECT_REMOTE_LOG_SELECTIONS};
  my $test_logging = $ENV{OBJECT_REMOTE_TEST_LOGGER};
  my %controller_should_log;
  
  unless (defined $ENV{OBJECT_REMOTE_LOG_FORWARDING} && $ENV{OBJECT_REMOTE_LOG_FORWARDING} ne '') {
    $ENV{OBJECT_REMOTE_LOG_FORWARDING} = 1;
  }
  
  if ($test_logging) {
    require Object::Remote::Logging::TestLogger;
    router->connect(Object::Remote::Logging::TestLogger->new(
      min_level => 'trace', max_level => 'error',
      level_names => Object::Remote::Logging->arg_levels(),
    ));
  }

  return unless defined $level && $level ne '';
  $format = "[%l %r] %s" unless defined $format;
  $selections = __PACKAGE__ unless defined $selections;
  %controller_should_log = _parse_selections($selections);

  {
    no warnings 'once';
    if (defined $Object::Remote::FatNode::REMOTE_NODE) {
      #the connection id for the remote node comes in later
      #as the controlling node inits remote logging
      router()->_remote_metadata({ connection_id =>  undef });
    } 
  }

  my $logger = Object::Remote::Logging::Logger->new(
    min_level => lc($level), format => $format,
    level_names => Object::Remote::Logging::arg_levels(),
  );

  router()->connect(sub { 
    my $controller = $_[1]->{controller};
    my $will_log = $controller_should_log{$controller};
    
    $will_log = $controller_should_log{'*'} unless defined $will_log;
    
    return unless $will_log;
    #skip things from remote hosts because they log to STDERR
    #when OBJECT_REMOTE_LOG_LEVEL is in effect
    return if $_[1]->{remote}->{connection_id};
    $logger
  });
}

#this is invoked by the controlling node
#on the remote nodes
sub init_remote_logging {
  my ($self, %controller_info) = @_;
  
  router()->_remote_metadata(\%controller_info);
  router()->_forward_destination($controller_info{router}) if $ENV{OBJECT_REMOTE_LOG_FORWARDING};
}

1;

__END__

=head1 NAME

Object::Remote::Logging - Logging subsystem for Object::Remote

=head1 SYNOPSIS

  use Object::Remote::Logging qw( :log :dlog arg_levels router );
  
  @levels = qw( trace debug verbose info warn error fatal );
  @levels = arg_levels(); #same result
  
  $ENV{OBJECT_REMOTE_LOG_LEVEL} = 'trace'; #or other level name
  $ENV{OBJECT_REMOTE_LOG_FORMAT} = '%l %t: %p::%m %s'; #and more
  $ENV{OBJECT_REMOTE_LOG_SELECTIONS} = 'Object::Remote::Logging Some::Other::Subclass';
  $ENV{OBJECT_REMOTE_LOG_SELECTIONS} = '* -Object::Remote::Logging';
  $ENV{OBJECT_REMOTE_LOG_FORWARDING} = 0; #default 1
  
  log_info { 'Trace log event' };
  Dlog_verbose { "Debug event with Data::Dumper::Concise: $_" } { foo => 'bar' };

=head1 DESCRIPTION

This is the logging framework for Object::Remote implemented as a subclass of
L<Log::Contextual> with a slightly incompatible API. This system allows 
developers using Object::Remote and end users of that software to control
Object::Remote logging so operation can be tracked if needed. This is also
the API used to generate log messages inside the Object::Remote source code.

The rest of the logging system comes from L<Object::Remote::Logging::Logger>
which implements log rendering and output and L<Object::Remote::Logging::Router>
which delivers log events to the loggers.

=head1 USAGE

Object::Remote logging is not enabled by default. If you need to immediately start
debugging set the OBJECT_REMOTE_LOG_LEVEL environment variable to either 'trace'
or 'debug'. This will enable logging to STDERR on the local and all remote Perl 
interpreters. By default STDERR for all remote interpreters is passed through
unmodified so this is sufficient to receive logs generated anywhere Object::Remote
is running.

Every time the local interpreter creates a new Object::Remote::Connection the connection
is given an id that is unique to that connection on the local interpreter. The connection
id and other metadata is available in the log output via a log format string that can
be set via the OBJECT_REMOTE_LOG_FORMAT environment variable. The format string and
available metadata is documented in L<Object::Remote::Logging::Logger>. Setting this
environment variable on the local interpreter will cause it to be propagated to the 
remote interpreter so all logs will be formated the same way.

This class is designed so any module can create their own logging sub-class using it.
With out any additional configuration the consumers of this logging class will
automatically be enabled via OBJECT_REMOTE_LOG_LEVEL and formated with 
OBJECT_REMOTE_LOG_FORMAT but those additional log messages are not sent to STDERR. 
By setting the  OBJECT_REMOTE_LOG_SELECTIONS environment variable to a list of
class names seperated by spaces then logs generated by packages that use those classes
will be sent to STDERR. If the asterisk character (*) is used in the place of a class
name then all class names will be selected by default instead of ignored. An individual
class name can be turned off by prefixing the name with a hypen character (-). This is
also a configuration item that is forwarded to the remote interpreters so all logging
is consistent.

Regardless of OBJECT_REMOTE_LOG_LEVEL the logging system is still active and loggers
can access the stream of log messages to format and output them. Internally
OBJECT_REMOTE_LOG_LEVEL causes an L<Object::Remote::Logging::Logger> to be built
and connected to the L<Object::Remote::Logging::Router> instance. It is also possible
to manually build a logger instance and connect it to the router. See the documentation
for the logger and router classes.

The logging system also supports a method of forwarding log messages from remote
interpreters to the local interpreter. Forwarded log messages are generated in the
remote interpreter and the logger for the message is invoked in the local interpreter.
Sub-classes of Object::Remote::Logging will have log messages forwarded automatically.
Loggers receive forwarded log messages exactly the same way as non-forwarded messages
except a forwarded message includes extra metadata about the remote interpreter. Log
forwarding is enabled by default but comes with a performance hit; to disable it set the 
OBJECT_REMOTE_LOG_FORWARDING environment variable to 0. See L<Object::Remote::Logging::Router>.

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
  %hash = Dlog_trace { "Very handy: $_" } ( foo => 'bar' );

=item logS_<level> and DlogS_<level>

Works just like log_ and Dlog_ except returns only the first argument as a scalar value.

  my $beverage = logS_info { "Customer ordered $_[0]" } 'Coffee';

=back

=head1 LEVEL NAMES

Object::Remote uses an ordered list of log level names with the lowest level
first and the highest level last. The list of level names can be accessed via
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
