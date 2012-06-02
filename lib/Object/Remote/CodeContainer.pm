package Object::Remote::CodeContainer;

use Moo;

has code => (is => 'ro', required => 1);

sub call { shift->code->(@_) }

1;
