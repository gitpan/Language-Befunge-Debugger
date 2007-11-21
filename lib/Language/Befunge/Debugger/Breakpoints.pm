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

#
# my $id = Language::Befunge::Debugger::Breakpoints->spawn( %opts );
#
# create a new debugger gui for a befunge script. refer to the embedded
# pod for an explanation of the supported options.
#
sub spawn {
    my ($class, %opts) = @_;

    my $session = POE::Session->create(
        inline_states => {
            _start     => \&_on_start,
            _stop      => sub { print "ouch!\n" },
            # public events
            breakpoint_add         => \&_do_breakpoint_add,
            visibility_toggle      => \&_do_visibility_toggle,
            # private events
            # gui events
            _b_breakpoint_remove   => \&_on_b_breakpoint_remove,
        },
        args => \%opts,
    );
    return $session->ID;
}


#--
# public events

#
# breakpoint_add( $brkpt );
#
# Add $brkpt to the list of breakpoints.
#
sub _do_breakpoint_add {
    my ($h, $brkpt) = @_[HEAP, ARG0];

    my @elems = $h->{list}->get(0, 'end');
    push @elems, $brkpt;

    $h->{list}->delete(0, 'end');
    $h->{list}->insert(0, sort @elems);
    $h->{but_remove}->configure(-state => 'normal' );
}


#
# visibility_toggle();
#
# Request window to be hidden / shown depending on its previous state.
#
sub _do_visibility_toggle {
    my ($h) = $_[HEAP];

    my $method = $h->{mw}->state eq 'normal' ? 'withdraw' : 'deiconify';
    $h->{mw}->$method;
}


#--
# private events

#
# _on_start( \%opts );
#
# session initialization. %opts is received from spawn();
#
sub _on_start {
    my ($k, $h, $from, $s, $opts) = @_[KERNEL, HEAP, SENDER, SESSION, ARG0];

    #-- create gui

    my $top = $opts->{parent}->Toplevel(-title => 'Breakpoints');
    $h->{mw}   = $top;
    $h->{list} = $top->Listbox->pack;
    $h->{but_remove} = $top->Button(
        -text    => 'Remove',
        -state   => 'disabled',
        -width   => 6,
        -command => $s->postback('_b_breakpoint_remove')
    )->pack(-side=>'left',-fill=>'x',-expand=>1);
    $top->Button(
        -text    => 'Close',
        -width   => 6,
        -command => $s->postback('visibility_toggle')
    )->pack(-side=>'left',-fill=>'x',-expand=>1);

    # trap some events
    $top->protocol( WM_DELETE_WINDOW => $s->postback('visibility_toggle') );
    $top->bind( '<F8>', $s->postback('visibility_toggle') );

    
    $top->update;               # force redraw
    $top->resizable(0,0);
    my ($maxw,$maxh) = $top->geometry =~ /^(\d+)x(\d+)/;
    $top->maxsize($maxw,$maxh); # bug in resizable: minsize in effet but not maxsize


    # -- other inits
    $h->{parent_session} = $from->ID;
    # initial breakpoint?
    $k->yield('breakpoint_add', $opts->{breakpoint}) if exists $opts->{breakpoint};
}


#--
# gui events

#
# _b_breakpoint_remove();
#
# called when the user wants to remove a breakpoint.
#
sub _on_b_breakpoint_remove {
    my ($k, $h) = @_[KERNEL, HEAP];
    my ($idx) = $h->{list}->curselection;
    my $brkpt = $h->{list}->get($idx);
    $h->{list}->delete($idx);
    $k->post( $h->{parent_session}, 'breakpoint_remove', $brkpt );
}


1;

__END__


=head1 NAME

Language::Befunge::Debugger::Breakpoints - a window listing breakpoints



=head1 SYNOPSYS

    my $id = Language::Befunge::Debugger::Breakpoints->spawn(%opts);
    $kernel->post( $id, 'visibility_toggle' );



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


=item breakpoint => $brkpt

An optional breakpoint to be added during session creation.


=back


=head1 PUBLIC EVENTS

The newly created POE session accepts the following events:


=over 4

=item breakpoint_add( $brkpt )

Add a breakpoint in the list of breakpoints.


=item visibility_toggle()

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

