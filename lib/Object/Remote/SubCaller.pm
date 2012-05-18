package Object::Remote::SubCaller;

use Module::Runtime qw(use_module);

sub new { bless({}, ref($_[0])||$_[0]) }

sub call {
  my ($self, $name, @args) = @_;
  my ($pkg, $sub_name) = $name =~ /^(.+)::([^:]+)$/
    or die "Couldn't split ${name} into package and sub";
  if (my $sub = use_module($pkg)->can($sub_name)) {
    return $sub->(@args);
  } else {
    die "No subroutine ${sub_name} in package ${pkg}";
  }
}

1;
