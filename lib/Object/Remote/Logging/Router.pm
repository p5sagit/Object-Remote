package Object::Remote::Logging::Router;

use Moo;

with 'Log::Contextual::Role::Router';
with 'Object::Remote::Role::LogForwarder';

has _controller_package => ( is => 'rwp' );
#lookup table for package names that should not
#be forwarded across Object::Remote connections
has _connections => ( is => 'ro', required => 1, default => sub { [] } );
has _remote_metadata => ( is => 'rw' );

sub before_import {
    my ($self, $controller, $importer, $spec) = @_;
}

sub after_import { }

sub _get_loggers {
    my ($self, %metadata) = @_;
    my $package = $metadata{package};
    my $level = $metadata{level};
    my $is_level = "is_$level";
    my $need_clean = 0;
    my @loggers;
    
    foreach my $selector (@{$self->_connections}) {
        unless(defined $selector) {
            $need_clean = 1;
            next;
        }
        
        foreach my $logger ($selector->($package, { %metadata })) {
            next unless defined $logger;
            next unless $logger->$is_level;
            push(@loggers, $logger);
        }
    }

    $self->_clean_connections if $need_clean;
    
    return @loggers; 
}

sub handle_log_request {
    my ($self, $metadata_in, $generator, @args) = @_;
    my %metadata = %{$metadata_in};
    my $level = $metadata{level};
    my $package = $metadata{package};
    my $need_clean = 0;

    #caller_level is useless when log forwarding is in place
    #so we won't tempt people with using it for now - access
    #to caller level will be available in the future
    delete $metadata{caller_level};
    $metadata{object_remote} = $self->_remote_metadata;
    
    foreach my $logger ($self->_get_loggers(%metadata)) {
        $logger->$level([ $generator->(@args) ], \%metadata);
    }
}

sub connect {
    my ($self, $destination) = @_;
    my $wrapped; 
        
    if (ref($destination) ne 'CODE') {
        $wrapped = sub { $destination };
    } else {
        $wrapped = $destination;
    }
    
    push(@{$self->_connections}, $wrapped);
}

sub _clean_connections {
    my ($self) = @_;
    @{$self->{_connections}} = grep { defined } @{$self->{_connections}};
}

1;
