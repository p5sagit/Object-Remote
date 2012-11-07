#require this file in the test to initialize the logging framework
#so the tests can run and all log items can be executed during testing

package Object::Remote::Logging::TestOutput;

use base qw ( Object::Remote::Logging::Logger );

#don't need to output anything
sub _output { }

package main; 

use Object::Remote::Logging qw( router ); 
#make sure to enable execution of every logging code block
#by setting the log level as high as it can go
router->connect(Object::Remote::Logging::TestOutput->new(
  min_level => 'trace', max_level => 'error',
  level_names => Object::Remote::Logging->arg_levels(),
));

1;

