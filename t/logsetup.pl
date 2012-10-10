#require this file in the test to initialize the logging framework
#so the tests can run

package Object::Remote::Logger::TestOutput; 

use base qw ( Log::Contextual::SimpleLogger );

#we want the code blocks in the log lines to execute but not
#output anything so turn this into a null logger
sub _log { }

package main; 

use Object::Remote::Logging qw( :log ); 
use Object::Remote::LogDestination; 
#make sure to enable execution of every logging code block
#by setting the log level as high as it can go
    my $____LOG_DESTINATION = Object::Remote::LogDestination->new(
        logger => Object::Remote::Logger::TestOutput->new({ levels_upto => 'trace' }),
    );  
    
    $____LOG_DESTINATION->connect(Object::Remote::Logging->arg_router);
1;

