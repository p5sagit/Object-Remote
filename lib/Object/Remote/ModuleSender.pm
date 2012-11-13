package Object::Remote::ModuleSender;

use Object::Remote::Logging qw( :log :dlog );
use Config;
use File::Spec;
use List::Util qw(first);
use Moo;

has dir_list => (is => 'lazy');

sub _build_dir_list {
  my %core = map +($_ => 1), grep $_, @Config{
    qw(privlibexp archlibexp vendorarchexp sitearchexp)
  };
  DlogS_trace { "dir list built in ModuleSender: $_" } [ grep !$core{$_}, @INC ];
}

sub source_for {
  my ($self, $module) = @_;
  log_debug { "locating source for module '$module'" };
  if (my $find = Object::Remote::FromData->can('find_module')) {
    if (my $source = $find->($module)) {
      Dlog_trace { "source of '$module' was found by Object::Remote::FromData" };
      return $source;
    }
  }
  log_trace { "Searching for module in library directories" };

  for my $inc (@{$self->dir_list}) {
    if (!ref $inc) {
      my $full_module = File::Spec->catfile($inc, $module);
      next unless -f $full_module;
      log_debug { "found '$module' at '$found'" };
      open my $fh, '<', $full_module or die "Couldn't open ${full_module} for ${module}: $!";
      return do { local $/; <$fh> };
    }
    else {
      my $data = _read_dynamic_inc($inc, $module);
      return $data
        if defined $data;
    }
  }
  die "Couldn't find ${module} in remote \@INC. dir_list contains:\n"
      .join("\n", @{$self->dir_list});
}

sub _read_dynamic_inc {
  my ($inc, $module) = @_;

  my ($fh, $cb, $state);
  if (ref $inc eq 'CODE') {
    ($fh, $cb, $state) = $inc->($inc, $module);
  }
  elsif (ref $inc eq 'ARRAY') {
    ($fh, $cb, $state) = $inc->[0]->($inc, $module);
  }
  elsif ($inc->can('INC')) {
    ($fh, $cb, $state) = $inc->INC($module);
  }

  if ($cb && $fh) {
    my $data = '';
    while (1) {
      local $_ = <$fh>;
      last unless defined;
      my $res = $cb->($cb, $state);
      $data .= $_;
      last unless $res;
    }
    return $data;
  }
  elsif ($cb) {
    my $data = '';
    while (1) {
      local $_;
      my $res = $cb->($cb, $state);
      $data .= $_;
      last unless $res;
    }
    return $data;
  }
  elsif ($fh) {
    return do { local $/; <$fh> };
  }
  return;
}

1;
