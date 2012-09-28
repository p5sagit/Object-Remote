package Object::Remote::Connector::SSH;

use Object::Remote::ModuleSender;
use Object::Remote::Handle;
use Moo;

with 'Object::Remote::Role::Connector::PerlInterpreter';

has ssh_to => (is => 'ro', required => 1);

has ssh_perl_command => (is => 'lazy');

has ssh_options => (is => 'ro', default => sub { [ '-A' ] });

has ssh_command => (is => 'ro', default => sub { 'ssh' });

#TODO properly integrate if this works
BEGIN { $ENV{TERM} = 'dumb'; } 

sub _escape_shell_arg { 
    my ($self, $str) = (@_);
    $str =~ s/((?:^|[^\\])(?:\\\\)*)'/$1\\'/g;
    return "$str";
}


sub _build_ssh_perl_command {
  my ($self) = @_;
  my $perl_command = join('', @{$self->perl_command});
  
  #TODO non-trivial to escape properly for ssh and shell
  #this "works" but is not right, needs to be replaced
  #after testing
  return [
    do { my $c = $self->ssh_command; ref($c) ? @$c : $c },
    @{$self->ssh_options}, $self->ssh_to,
    $self->_escape_shell_arg($perl_command),
  ];
}

sub final_perl_command { shift->ssh_perl_command }

no warnings 'once';

push @Object::Remote::Connection::Guess, sub { 
  for ($_[0]) {
    # 0-9 a-z _ - first char, those or . subsequent - hostnamish
    if (defined and !ref and /^(?:.*?\@)?[\w\-][\w\-\.]/) {
      my $host = shift(@_);
      return __PACKAGE__->new(@_, ssh_to => $host);
    }
  }
  return;
};

1;
