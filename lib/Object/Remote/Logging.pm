package Object::Remote::Logging;

use strictures 1;

use Log::Contextual::Routed qw( :log );
use base qw(Log::Contextual::Routed); 

sub get_parent_router { $_[0]->SUPER::get_parent_router }

use Data::Dumper; 

sub init_node { my $n = `hostname`; chomp($n); $_[0]->add_child_router("[node $n]", __PACKAGE__->get_root_router) }

1;

