package Object::Remote::Logging::Router;

use Moo;
use Scalar::Util qw(weaken);

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
      my $method = $logger->can($is_level);
      next unless defined $method;
      next unless $logger->$method;
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
  my $caller_level = delete $metadata{caller_level};
  $metadata{object_remote} = $self->_remote_metadata;
  $metadata{timestamp} = time;

  my @caller_info = caller($caller_level);
  $metadata{filename} = $caller_info[1];
  $metadata{line} = $caller_info[2];
 
  @caller_info = caller($caller_level + 1);
  $metadata{method} = $caller_info[3];
  $metadata{method} =~ s/^${package}::// if defined $metadata{method};
  
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
  weaken($self->_connections->[-1]);
}

sub _clean_connections {
  my ($self) = @_;
  @{$self->{_connections}} = grep { defined } @{$self->{_connections}};
}

1;
