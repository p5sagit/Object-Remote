use strictures 1;
use Test::More;
use Test::Fatal;

$ENV{PERL5LIB} = join(
  ':', ($ENV{PERL5LIB} ? $ENV{PERL5LIB} : ()), qw(lib t/lib)
);

use Object::Remote;

my $strA = 'foo';
my $strB = 'bar';

is exception {
  my $proxy = ORTestTransfer->new::on('-', value => \$strA);
  is_deeply $proxy->value, \$strA, 'correct value after construction';
}, undef, 'no errors during construction';

is exception {
  my $proxy = ORTestTransfer->new::on('-');
  $proxy->value(\$strB);
  is_deeply $proxy->value, \$strB, 'correct value after construction';
}, undef, 'no errors during attribute set';

done_testing;
