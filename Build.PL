#!perl
#
# This file is part of Language::Befunge::Debugger.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
#

use strict;
use warnings;

use Module::Build;
my $builder = Module::Build->new
  ( module_name       => 'Language::Befunge::Debugger',
    license           => 'perl',
    dist_author       => 'Jerome Quelin <jquelin@cpan.org>',
    dist_version_from => 'lib/Language/Befunge/Debugger.pm',
    build_requires    => {
        'perl'              => '5.008',
        'Getopt::Euclid'    => 0,
        'Language::Befunge' => 3.01,
        'POE'               => 0,
        'Readonly'          => 0,
        'Test::More'        => 0,
        'Tk'                => 0,
        'Tk::TableMatrix'   => 0,
        'Tk::ToolBar'       => 0,
    },
    requires          => {
        'Getopt::Euclid'    => 0,
        'Language::Befunge' => 3.01,
        'POE'               => 0,
        'Readonly'          => 0,
        'Tk'                => 0,
        'Tk::TableMatrix'   => 0,
        'Tk::ToolBar'       => 0,
    },
    #recommends        => { 'Test::Exception' => 0 },
    script_files      => [ 'bin/jqbefdb' ],
    add_to_cleanup    =>
      [ 'Language-Befunge-Debugger-*', 'MANIFEST.bak',
        map { ( '*/' x $_ ) . '*~' } 0..5 ],
    #recursive_test_files => 1
  );
$builder->create_build_script;

