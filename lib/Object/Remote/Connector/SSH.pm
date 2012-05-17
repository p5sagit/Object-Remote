package Object::Remote::Connector::SSH;

use Object::Remote::FatNode;
use Net::OpenSSH;
use Moo;

with 'Object::Remote::Role::Connector';

has ssh_masters => (is => 'ro', default => sub { {} });

sub _open2_for {
  my $self = shift;
  my @res = $self->_ssh_object_for(@_)->open2('perl','-',@_);
  print { $res[0] } $Object::Remote::FatNode::DATA, "__END__\n";
  return @res;
}

sub _ssh_object_for {
  my ($self, $on) = @_;
  $self->ssh_masters->{$on} ||= Net::OpenSSH->new($on);
}

1;
