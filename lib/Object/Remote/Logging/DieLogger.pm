package Object::Remote::Logging::DieLogger;

use Moo;

extends 'Object::Remote::Logging::Logger';

has format => ( is => 'ro', required => 1, default => sub { '%s at %f line %i' } );
has max_level => ( is => 'ro', required => 1, default => sub { 'fatal' } );
has min_level => ( is => 'ro', required => 1, default => sub { 'fatal' } );

sub output { die $_[1] };

1;
