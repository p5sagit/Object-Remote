package Object::Remote::ModuleLoader;

BEGIN {
  package Object::Remote::ModuleLoader::Hook;
  use Moo;
  use Object::Remote::Logging qw( :log :dlog );
  has sender => (is => 'ro', required => 1);

  # unqualified INC forced into package main
  sub Object::Remote::ModuleLoader::Hook::INC {
    my ($self, $module) = @_;
    log_debug { "Loading $module via " . ref($self) };
    if (my $code = $self->sender->source_for($module)) {
      open my $fh, '<', \$code;
      Dlog_trace { "Module sender successfully sent code for '$module': $code" } $code;
      return $fh;
    }
    log_trace { "Module sender did not return code for '$module'" };
    return;
  }
}

use Moo;

use Object::Remote::Logging qw( :log );

has module_sender => (is => 'ro', required => 1);

has inc_hook => (is => 'lazy');

sub _build_inc_hook {
  my ($self) = @_;
  log_debug { "Constructing module builder hook" };
  my $hook = Object::Remote::ModuleLoader::Hook->new(sender => $self->module_sender);
  log_trace { "Done constructing module builder hook" };
  return $hook;
}

sub BUILD { shift->enable }

sub enable {
  log_debug { "enabling module loader hook" };
  push @INC, shift->inc_hook;
  return;
}

sub disable {
  my ($self) = @_;
  log_debug { "disabling module loader hook" };
  my $hook = $self->inc_hook;
  @INC = grep $_ ne $hook, @INC;
  return;
}

sub DEMOLISH { $_[0]->disable unless $_[1] }

1;
