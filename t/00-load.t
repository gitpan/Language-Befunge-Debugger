#!perl
#
# This file is part of Language::Befunge.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
#

use strict;
use warnings;

use Test::More tests => 1;
require_ok( 'Language::Befunge::Debugger' );
diag( "Testing Language::Befunge::Debugger $Language::Befunge::Debugger::VERSION Perl $], $^X" );

exit;
