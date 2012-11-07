package Object::Remote::Logging::Logger;

use Moo;
use Scalar::Util qw(weaken);

has format => ( is => 'ro', required => 1, default => sub { '[%l %r] %f:%i %p::%m %s' } );
has level_names => ( is => 'ro', required => 1 );
has min_level => ( is => 'ro', required => 1 );
has max_level => ( is => 'ro' );
has _level_active => ( is => 'lazy' );

sub BUILD {
  my ($self) = @_;
  our $METHODS_INSTALLED; 
  $self->_install_methods unless $METHODS_INSTALLED;
}

sub _build__level_active {
  my ($self) = @_; 
  my $should_log = 0;
  my $min_level = $self->min_level;
  my $max_level = $self->max_level;
  my %active;
    
  foreach my $level (@{$self->level_names}) {
    if($level eq $min_level) {
      $should_log = 1; 
    }

    $active{$level} = $should_log;
        
    if (defined $max_level && $level eq $max_level) {
      $should_log = 0;
    }
  }

  return \%active;
}

sub _install_methods {
  my ($self) = @_;
  my $should_log = 0;
  our $METHODS_INSTALLED = 1;

  no strict 'refs';

  foreach my $level (@{$self->level_names}) {
    *{"is_$level"} = sub { shift(@_)->_level_active->{$level} };
    *{$level} = sub { shift(@_)->_log($level, @_) };
  }
}

sub _log {
  my ($self, $level, $content, $metadata_in) = @_;
  my %metadata = %$metadata_in;
  my $rendered = $self->_render($level, \%metadata, @$content);
  $self->_output($rendered);
}

sub _create_format_lookup {
  my ($self, $level, $metadata, $content) = @_;
  return { 
    '%' => '%', t => $self->_render_time($metadata->{timestamp}),
    r => $self->_render_remote($metadata->{object_remote}),
    s => $self->_render_log(@$content), l => $level, 
    p => $metadata->{package}, m => $metadata->{method},
    f => $metadata->{filename}, i => $metadata->{line},
    
  };
}

sub _get_format_var_value {
  my ($self, $name, $data) = @_;
  my $val = $data->{$name};
  return $val if defined $val;
  return '';
}

sub _render_time {
  my ($self, $time) = @_;
  return scalar(localtime($time));
}

sub _render_remote {
  my ($self, $remote) = @_;
  return 'local' if ! defined $remote || ! defined $remote->{connection_id};
  return 'remote #' . $remote->{connection_id};
}

sub _render_log {
  my ($self, @content) = @_;
  return join('', @content);
}
sub _render {
  my ($self, $level, $metadata, @content) = @_;
  my $var_table = $self->_create_format_lookup($level, $metadata, [@content]);
  my $template = $self->format;
  
  $template =~ s/%([\w])/$self->_get_format_var_value($1, $var_table)/ge;
  
  chomp($template);
  $template =~ s/\n/\n /g;
  $template .= "\n";
  return $template;
}

sub _output {
  my ($self, $content) = @_;
  print STDERR $content;
}


1;

