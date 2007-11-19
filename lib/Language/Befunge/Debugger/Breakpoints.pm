#
# This file is part of Language::Befunge::Debugger.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#

package Language::Befunge::Debugger::Breakpoints;

use strict;
use warnings;

use Readonly;
use Tk; # should come before POE
use Tk::Dialog;
use Tk::FBox;
use Tk::TableMatrix;
use Tk::ToolBar;
use POE;

#--
# constructor

sub spawn {
    my ($class, %opts) = @_;

    my $session = POE::Session->create(
        inline_states => {
            _start     => \&_on_start,
            _stop      => sub { print "ouch!\n" },
            # public events
            toggle_visibility => \&_do_toggle_visibility,
            # private events
            # gui
        },
        args => \%opts,
    );
    return $session->ID;
}


#--
# public events

sub _do_toggle_visibility {
    my ($h) = $_[HEAP];

    my $method = $h->{mw}->state eq 'normal' ? 'withdraw' : 'deiconify';
    $h->{mw}->$method;
}


#--
# private events

sub _on_start {
    my ($k, $h, $s, $opts) = @_[KERNEL, HEAP, SESSION, ARG0];

    #-- create gui

    my $top = $opts->{parent}->Toplevel(-title => 'Breakpoints');
    $h->{mw}   = $top;
    $h->{list} = $top->Listbox->pack;
    $top->Button(-text=>'Remove', -width=>6,
        -command=>$s->postback('toggle_visibility'))->pack(-side=>'left',-fill=>'x',-expand=>1);
    $top->Button(-text=>'Close', -width=>6,
        -command=>$s->postback('toggle_visibility'))->pack(-side=>'left',-fill=>'x',-expand=>1);
    $top->protocol( WM_DELETE_WINDOW => $s->postback('toggle_visibility') );

    $top->bind( '<F8>', $s->postback('toggle_visibility') );

    
    $top->update;               # force redraw
    $top->resizable(0,0);
    my ($maxw,$maxh) = $top->geometry =~ /^(\d+)x(\d+)/;
    $top->maxsize($maxw,$maxh); # bug in resizable: minsize in effet but not maxsize
}

1;

__END__


=head1 NAME

Language::Befunge::Debugger::Breakpoints - a window listing breakpoints



=head1 SYNOPSYS

    my $id = Language::Befunge::Debugger::Breakpoints->spawn(%opts);
    $kernel->post( $id, 'toggle_visibility' );



=head1 DESCRIPTION

LBD::Breakpoints implements a POE session, creating a Tk window listing
the breakpoints set in a debugger session. The window can be hidden at
will.



=head1 CLASS METHODS

=head2 my $id = Language::Befunge::Debugger::Breakpoints->spawn( %opts );

Create a window listing breakpoints, and return the associated POE
session ID. One can pass the following options:

=over 4

=item parent => $mw

A Tk window that will be the parent of the toplevel window created. This
parameter is mandatory.


=back


=head1 PUBLIC EVENTS

The newly created POE session accepts the following events:

=over 4

=item toggle_visibility()

Request the window to be hidden or restaured, depending on its previous
state. Note that closing the window is actually interpreted as hiding
the window.


=back



=head1 SEE ALSO

L<Language::Befunge::Debugger>.



=head1 AUTHOR

Jerome Quelin, C<< <jquelin at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright (c) 2007 Jerome Quelin, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=cut

