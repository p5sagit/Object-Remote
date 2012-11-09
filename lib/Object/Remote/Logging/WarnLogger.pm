package Object::Remote::Logging::WarnLogger;

use Moo;

extends 'Object::Remote::Logging::Logger';

has format => ( is => 'ro', required => 1, default => sub { '%s at %f line %i, log level: %l' } );
has min_level => ( is => 'ro', required => 1, default => sub { 'warn' } );

sub output { warn $_[1] };

1;
