package Object::Remote::FatNode;

use strictures 1;
use Config;
use B qw(perlstring);

my @exclude_mods = qw(XSLoader.pm DynaLoader.pm);
#used by t/watchdog_fatnode
our $INHIBIT_RUN_NODE = 0;

sub stripspace {
  my ($text) = @_;
  $text =~ /^(\s+)/ && $text =~ s/^$1//mg;
  $text;
}

my %maybe_libs = map +($_ => 1), grep defined, (values %Config, '.');

my @extra_libs = grep not(ref($_) or $maybe_libs{$_}), @INC;

my $extra_libs = join '', map qq[  -I"$_"\n], @extra_libs;
my $perl_quote = $^O eq "MSWin32" ? q["] : q['];

my $command = qq(
  $^X
  $extra_libs
  -mObject::Remote
  -mObject::Remote::Connector::STDIO
  -mFuture
  -mMRO::Compat
  -mClass::C3
  -mClass::C3::next
  -mAlgorithm::C3
  -mObject::Remote::ModuleLoader
  -mObject::Remote::Node
  -mMethod::Generate::BuildAll
  -mMethod::Generate::DemolishAll
  -mJSON::PP
  -e $perl_quote print join qq[\\n], \%INC $perl_quote
);

$command =~ s/\n/ /g;

chomp(my @inc = qx($command));

my %exclude = map { $_ => 1 } @exclude_mods;
my %mods = reverse @inc;
my %file_names = @inc;

foreach(keys(%mods)) {
  if ($exclude{ $mods{$_} }) {
    delete($mods{$_});
  }
}

my @non_core_non_arch = ( $file_names{'Devel/GlobalDestruction.pm'} );
push @non_core_non_arch, grep +(
  not (
    #some of the config variables can be empty which will eval as a matching regex
    $Config{privlibexp} ne '' && /^\Q$Config{privlibexp}/
      or $Config{archlibexp} ne '' && /^\Q$Config{archlibexp}/
      or $Config{vendorarchexp} ne '' && /^\Q$Config{vendorarchexp}/
      or $Config{sitearchexp} ne '' && /^\Q$Config{sitearchexp}/
  )
), grep !/\Q$Config{archname}/, grep !/\Q$Config{myarchname}/, keys %mods;

my @core_non_arch = grep +(
  $Config{privlibexp} ne '' && /^\Q$Config{privlibexp}/
  and not($Config{archlibexp} ne '' && /^\Q$Config{archlibexp}/
    or /\Q$Config{archname}/ or /\Q$Config{myarchname}/)
), keys %mods;

my $start = stripspace <<'END_START';
  # This chunk of stuff was generated by Object::Remote::FatNode. To find
  # the original file's code, look for the end of this BEGIN block or the
  # string 'FATPACK'
  BEGIN {
  my (%fatpacked,%fatpacked_extra);
END_START

$start .= 'my %exclude = map { $_ => 1 } (\'' . join("','", @exclude_mods) . "');\n";

my $end = stripspace <<'END_END';
  s/^  //mg for values %fatpacked, values %fatpacked_extra;

  sub load_from_hash {
    if (my $fat = $_[0]->{$_[1]}) {
      if ($exclude{$_[1]}) {
        warn "Will not pre-load '$_[1]'";
        return undef;
      }

      #warn "Handling $_[1]";
      open my $fh, '<', \$fat;
      return $fh;
    }

    #Uncomment this to find brokenness
    #warn "Missing $_[1]";
    return;
  }

  unshift @INC, sub { load_from_hash(\%fatpacked, $_[1]) };
  push @INC, sub { load_from_hash(\%fatpacked_extra, $_[1]) };

  } # END OF FATPACK CODE

  use strictures 1;
  use Object::Remote::Node;

  unless ($Object::Remote::FatNode::INHIBIT_RUN_NODE) {
    Object::Remote::Node->run(watchdog_timeout => $WATCHDOG_TIMEOUT);
  }

END_END

my %files = map +($mods{$_} => scalar do { local (@ARGV, $/) = ($_); <> }),
              @non_core_non_arch, @core_non_arch;

sub generate_fatpack_hash {
  my ($hash_name, $orig) = @_;
  (my $stub = $orig) =~ s/\.pm$//;
  my $name = uc join '_', split '/', $stub;
  my $data = $files{$orig} or die $orig; $data =~ s/^/  /mg;
  $data .= "\n" unless $data =~ m/\n$/;
  my $ret = '$'.$hash_name.'{'.perlstring($orig).qq!} = <<'${name}';\n!
    .qq!${data}${name}\n!;
#  warn $ret;
  return $ret;
}

my @segments = (
  map(generate_fatpack_hash('fatpacked', $_), sort map $mods{$_}, @non_core_non_arch),
  map(generate_fatpack_hash('fatpacked_extra', $_), sort map $mods{$_}, @core_non_arch),
);

#print STDERR Dumper(\@segments);
our $DATA = join "\n", $start, @segments, $end;

1;
