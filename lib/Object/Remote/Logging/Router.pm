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

sub _invoke_logger {
  my ($self, $logger, $level_name, $content, $metadata) = @_;
  #Invoking the logger like this gets all available data to the
  #logging object with out losing any information from the structure.
  #This is not a backwards compatible way to invoke the loggers
  #but it enables a lot of flexibility in the logger.
  #The l-c router could have this method invoke the logger in
  #a backwards compatible way and router sub classes invoke
  #it in non-backwards compatible ways if desired
  $logger->$level_name($content, $metadata);
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
    $self->_invoke_logger($logger, $level, [ $generator->(@args) ], \%metadata);
  }
}

sub connect {
  my ($self, $destination, $is_weak) = @_;
  my $wrapped; 

  if (ref($destination) ne 'CODE') {
    $wrapped = sub { $destination };
  } else {
    $wrapped = $destination;
  }

  push(@{$self->_connections}, $wrapped);
  weaken($self->_connections->[-1]) if $is_weak;
}

sub _clean_connections {
  my ($self) = @_;
  @{$self->{_connections}} = grep { defined } @{$self->{_connections}};
}

1;
