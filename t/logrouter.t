use strictures 1;
use Test::More;
use Sys::Hostname;

$ENV{OBJECT_REMOTE_TEST_LOGGER} = 1;

use Object::Remote::Logging::Router;

my $controller_name = 'Test::Log::Controller';
my $generator = sub { "Generator output" };
my $metadata = {
  controller => $controller_name, package => __PACKAGE__, level => 'test1',
  caller_level => 0,
};

my $router = Object::Remote::Logging::Router->new;
$router->_remote_metadata({ router => undef, connection_id => 'TestConnectionId' });
isa_ok($router, 'Object::Remote::Logging::Router');
ok($router->does('Log::Contextual::Role::Router'), 'Router does router role');

require 't/lib/ORFeedbackLogger.pm';
my $logger = ORFeedbackLogger->new(level_names => [qw( test1 test2 )], min_level => 'test1');

my $selector = sub { $logger };
$router->connect($selector, 1);
ok($router->_connections->[0] eq $selector, 'Selector is stored in connections');
ok(scalar(@{$router->_connections} == 1), 'There is a single connection');

$logger->reset;
my $linenum = __LINE__ + 1;
$router->handle_log_request($metadata, $generator);
is($logger->feedback_output, "test1: Generator output\n", 'Rendered log message is correct');
ok($logger->feedback_input->[2]->{timestamp} > 0, 'Timestamp value is present');
delete $logger->feedback_input->[2]->{timestamp};
is_deeply($logger->feedback_input, [
  'test1', [ 'Generator output' ], {
    controller => 'Test::Log::Controller', level => 'test1',
    hostname => hostname(), pid => $$, package => __PACKAGE__,
    line => $linenum, method => undef, filename => __FILE__,
    object_remote => {
      connection_id => 'TestConnectionId', router => undef,
    },
  },
], 'Input to logger was correct');

$logger->reset;
undef($selector);
$router->handle_log_request($metadata, $generator);
ok(scalar(@{$router->_connections}) == 0, 'Selector has been disconnected');
ok(! defined $logger->feedback_output, 'Logger has no output feedback');
ok(! defined $logger->feedback_input, 'Logger has no input feedback');

$router->connect($logger);
ok(scalar(@{$router->_connections} == 1), 'There is a single connection');
undef($logger);
$router->handle_log_request($metadata, $generator);
ok(scalar(@{$router->_connections} == 1), 'Connection is still active');

done_testing;
