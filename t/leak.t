use strictures;

use Test::More;

use Scalar::Util 'weaken';
use Object::Remote::FromData;

my $conn_ref;
{
    my $conn = Object::Remote->connect( '-' );
    $conn_ref = \( $conn->{send_to_fh} );
    weaken $conn_ref;
    is My::TestClass->new::on( $conn )->run, 3, "correct output";
}
sleep 3;
is $$conn_ref, undef, "filehandle to ssh's STDIN is garbage-collected";

done_testing;

__DATA__

package My::TestClass;
use Moo;
sub run { "3" }
