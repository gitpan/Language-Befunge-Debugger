#!perl
#
# This file is part of Language::Befunge::Debugger.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
#

BEGIN { require 5.008; }
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Language::Befunge::Debugger',
    AUTHOR              => 'Jerome Quelin <jquelin@cpan.org>',
    LICENSE             => 'perl',
    VERSION_FROM        => 'lib/Language/Befunge/Debugger.pm',
    ABSTRACT_FROM       => 'lib/Language/Befunge/Debugger.pm',
    EXE_FILES           => [ 'bin/jqbefdb' ],
    PREREQ_PM => {
        'Language::Befunge' => 3.01,
        'POE'               => 0,
        'Readonly'          => 0,
        'Tk'                => 0,
        'Tk::TableMatrix'   => 0,
        'Tk::ToolBar'       => 0,
        'Test::More'        => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => [
                'Language-Befunge-Debugger-*', 'MANIFEST.bak',
                map { ( '*/' x $_ ) . '*~' } 0..5
        ] },
);
