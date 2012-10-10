use strictures 1;
use Test::More;

require 't/logsetup.pl';

use Object::Remote::Connector::Local; 

$SIG{ALRM} = sub { die "alarm signal\n" };

open(my $nullfh, '>', '/dev/null') or die "Could not open /dev/null: $!";

my $fatnode_text = Object::Remote::Connector::Local->new(watchdog_timeout => 1)->fatnode_text; 

#this simulates a node that has hung before it reaches
#the watchdog initialization - it's an edge case that
#could cause remote processes to not get cleaned up
#if it's not handled right
eval {
  no warnings 'once';
  local *STDOUT = $nullfh;
  $Object::Remote::FatNode::INHIBIT_RUN_NODE = 1; 
  eval $fatnode_text;
  
  if ($@) {
      die "could not eval fatnode text: $@";
  } 
  
  while(1) {
      sleep(1);
  }
};

is($@, "alarm signal\n", "Alarm handler was invoked");

done_testing; 

