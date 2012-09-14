package Object::Remote::Logging;

use strictures 1;

use Log::Contextual qw( :log );
use Object::Remote::LogRouter;

use base qw(Log::Contextual); 

sub arg_router { return $_[1] if defined $_[1]; our $Router_Instance ||= Object::Remote::LogRouter->new }

sub init_node { my $n = `hostname`; chomp($n); $_[0]->add_child_router("[node $n]", __PACKAGE__->arg_router) }

1;

