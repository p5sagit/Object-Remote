use strictures 1;
use Test::More;

{
  package S1S;

  use Moo;

  sub get_s2 {
    S2S->new
  }
}

{
  package S1F;

  use Object::Remote::Future;
  use Moo;

  our $C;

  sub get_s2 {
    future {
      my $f = shift;
      $C = sub { $f->done(S2F->new); undef($f); };
      $f;
    }
  }
}

{
  package S2S;

  use Moo;

  sub get_s3 { 'S3' }
}

{
  package S2F;

  use Object::Remote::Future;
  use Moo;

  our $C;

  sub get_s3 {
    future {
      my $f = shift;
      $C = sub { $f->done('S3'); undef($f); };
      $f;
    }
  }
}

my $res;

S1S->start::get_s2->then::get_s3->on_ready(sub { ($res) = $_[0]->get });

is($res, 'S3', 'Synchronous code ok');

undef($res);

S1F->start::get_s2->then::get_s3->on_ready(sub { ($res) = $_[0]->get });

ok(!$S2F::C, 'Second future not yet constructed');

$S1F::C->();

ok($S2F::C, 'Second future constructed after first future completed');

ok(!$res, 'Nothing happened yet');

$S2F::C->();

is($res, 'S3', 'Asynchronous code ok');

done_testing;
