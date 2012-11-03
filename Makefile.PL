use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

(do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';

WriteMakefile(
  NAME => 'Object::Remote',
  VERSION_FROM => 'lib/Object/Remote.pm',
  PREREQ_PM => {
    Moo => 1.000005,
    'Module::Runtime' => 0.013,
    'JSON::PP' => 2.27200,
    'CPS::Future' => 0.17,
    'Class::C3' => 0.24, # required to fatpack Moo
  },
  EXE_FILES => [
    'bin/object-remote-node',
    'bin/object-remote-slave',
    'bin/remoterepl',
  ],
);
