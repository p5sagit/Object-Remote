package Object::Remote::ModuleSender;

use Object::Remote::Logging qw( :log :dlog );
use Config;
use File::Spec;
use List::Util qw(first);
use Moo;
use Scalar::Util qw(reftype openhandle blessed);

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
      log_trace { "source of '$module' was found by Object::Remote::FromData" };
      return $source;
    }
  }
  log_trace { "Searching for module in library directories" };

  for my $inc (@{$self->dir_list}) {
    if (!ref $inc) {
      my $full_module = File::Spec->catfile($inc, $module);
      next unless -f $full_module;
      log_debug { "found '$module' at '$full_module'" };
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

  my @cb = ref $inc eq 'ARRAY'  ? $inc->[0]->($inc, $module)
         : blessed $inc         ? $inc->INC($module)
                                : $inc->($inc, $module);

  my $fh;
  if (reftype $cb[0] eq 'GLOB' && openhandle $cb[0]) {
    $fh = shift @cb;
  }

  if (ref $cb[0] eq 'CODE') {
    log_debug { "found '$module' using $_" }, $inc;
    my $cb = shift @cb;
    # require docs are wrong, perl sends 0 as the first param
    my @params = (0, @cb ? $cb[0] : ());

    my $continue = 1;
    my $module = '';
    while ($continue) {
      local $_ = $fh ? <$fh> : '';
      $_ = ''
        if !defined;
      $continue = $cb->(@params);
      $module .= $_;
    }
    return $module;
  }
  elsif ($fh) {
    log_debug { "found '$module' using $_" }, $inc;
    return do { local $/; <$fh> };
  }
  return;
}

1;
