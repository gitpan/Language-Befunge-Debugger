#
# This file is part of Language::Befunge.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#

package Language::Befunge::Debugger;

use strict;
use warnings;

use Language::Befunge;
use Language::Befunge::Vector;
use Readonly;
use Tk; # should come before POE
use Tk::Dialog;
use Tk::TableMatrix;
use POE;


our $VERSION = '0.1.0';
Readonly my $DECAY => 8;

#--
# constructor

sub spawn {
    my ($class, %opts) = @_;

    POE::Session->create(
        inline_states => {
            _start     => \&_on_start,
            # gui
            _b_next     => \&_on_b_next,
            _b_quit     => \&_on_b_quit,
            _tm_click   => \&_on_tm_click,
        },
        args => \%opts,
    );
}

#--
# private events

sub _on_start {
    my ($k, $h, $s, $opts) = @_[ KERNEL, HEAP, SESSION, ARG0 ];

    #-- load befunge file
    # FIXME: barf unless file exists
    my $bef = $h->{bef} = Language::Befunge->new( $opts->{file} );
    $bef->set_ips( [ Language::Befunge::IP->new($bef->get_dimensions) ] );
    $bef->set_retval(0);


    #-- create gui

    my $fh1 = $poe_main_window->Frame->pack(-fill=>'both', -expand=>1);
    my $tm = $fh1->Scrolled( 'TableMatrix',
        -bg         => 'white',
        -scrollbars => 'osoe',
        -cols       => 80,
        -rows       => 25,
        -colwidth   => 3,
        -state      => 'disabled',
        -command    => sub { _get_cell_value($h->{bef}->get_torus,@_[1,2]) },
        -browsecmd  => $s->postback('_tm_click'),
    )->pack(-side=>'left', -fill=>'both', -expand=>1);
    $h->{w}{tm} = $tm;

    # buttons
    my $fv = $fh1-> Frame->pack(-fill=>'x');
    my $fh11 = $fv->Frame->pack;
    my $b_quit = $fh11->Button(
        -text    => 'Quit',
        -command => $s->postback('_b_quit'),
    )->pack(-side=>'left');
    my $b_restart = $fh11->Button(
        -text    => 'Restart',
        -command => $s->postback('_b_restart'),
    )->pack(-side=>'left');
    my $fh12 = $fv->Frame->pack;
    my $b_pause = $fh12->Button(
        -text    => '||',
        -command => $s->postback('_b_pause'),
    )->pack(-side=>'left');
    my $b_next = $fh12->Button(
        -text    => '>',
        -command => $s->postback('_b_next'),
    )->pack(-side=>'left');
    my $b_continue = $fh12->Button(
        -text    => '>>',
        -command => $s->postback('_b_continue'),
    )->pack(-side=>'left');

    # current position
    my $vec = Language::Befunge::Vector->new_zeroes(2);
    my $val = $h->{bef}->get_torus->get_value($vec);
    my $chr = chr $val;
    my $l_curpos = $h->{w}{l_curpos} = $poe_main_window->Label(
        -text    => "Position: (0,0) $chr (ord=$val)",
        -justify => 'left',
        -anchor  => 'w'
    )->pack(-fill=>'x', -expand=>1);

    # stack
    my $l_stack = $h->{w}{l_stack} = $poe_main_window->Label(
        -text    => 'Stack = []',
        -justify => 'left',
        -anchor  => 'w'
    )->pack(-fill=>'x', -expand=>1);

    #FIXME: lists of ips

    #-- various initializations
    $tm->tagCell( 'current', '0,0' );
    $tm->tagConfigure( 'current', -bg => 'red' );
    # color decay.
    foreach my $i ( 0 .. $DECAY-1 ) {
        my $v = sprintf "%02x", 255 / $DECAY * ($i+1);
        $tm->tagConfigure( "decay$i", -bg => "#ff$v$v" );
    }
}

#--
# gui events

sub _on_b_next {
    my ($h) = $_[HEAP];

    my $bef = $h->{bef};
    my $tm  = $h->{w}{tm};

    if ( scalar @{ $bef->get_ips } == 0 ) {
        # no more ip - end of program
        return;
    }

    # get next ip
    my $ip = shift @{ $bef->get_ips };
    my $id = $ip->get_id;
    $h->{oldpos}{$id} ||= [];

    # do some color decay.
    my $oldpos = $h->{oldpos}{$id};
    unshift @$oldpos, _vec_to_tablematrix_index($ip->get_position);
    pop     @$oldpos if scalar @$oldpos > $DECAY;
    foreach my $i ( 0 .. $DECAY-1 ) {
        last unless exists $oldpos->[$i];
        $tm->tagCell("decay$i", $h->{oldpos}{$id}[$i]);
    }



    # update gui

    # advance next ip
    $bef->set_curip($ip);
    $bef->process_ip;

    # update gui
    my $vec = $ip->get_position;
    my $val = $bef->get_torus->get_value($vec);
    my $chr = chr $val;
    my ($curx, $cury) = $vec->get_all_components;
    $tm->see("$cury,$curx");
    $tm->tagCell( 'current', "$cury,$curx" );
    # FIXME: more than 1 ip = different colors
    my $stack = $ip->get_toss;
    $h->{w}{l_stack} ->configure( -text => "Stack = [@$stack]" );
    $h->{w}{l_curpos}->configure( -text => "Position: ($curx,$cury) $chr (ord=$val)" );


    # end of tick: no more ips to process
    if ( scalar @{ $bef->get_ips } == 0 ) {
        $bef->set_ips( $bef->get_newips );
        $bef->set_newips( [] );
    }


}

sub _on_b_quit {
    $poe_main_window->destroy;
    #exit;
}

sub _on_tm_click {
    my ($h, $arg) = @_[HEAP, ARG1];
    my ($old, $new) = @$arg;
    my ($x,$y) = split /,/, $new;
    my $vec = Language::Befunge::Vector->new(2, $y, $x);
    my $val = $h->{bef}->get_torus->get_value($vec);
    my $chr = chr $val;
    $poe_main_window->Dialog( -text => "($x,$y) = $val = '$chr'" )->Show;
}


#--
# private subs

sub _get_cell_value {
    my ($torus, $row, $col) = @_;
    my $v = Language::Befunge::Vector->new(2, $col, $row);
    return chr( $torus->get_value($v) );
}

sub _vec_to_tablematrix_index {
    my ($vec) = @_;
    my ($x, $y) = $vec->get_all_components;
    return "$y,$x";
}


1;

__END__


=head1 NAME

Language::Befunge::Debugger - a graphical debugger for Language::Befunge



=head1 SYNOPSYS

    $ jqbefdb



=head1 DESCRIPTION

Language::Befunge::Debugger provides you with a graphical debugger for
Language::Befunge. This allow to follow graphically your befunge program
while it gets executed, update the stack and the playfield, add
breakpoints, etc.



=head1 CLASS METHODS

=head2 Language::Befunge::Debugger->spawn( %opts );

Create a graphical debugger (a POE session). One can pass the following
options:

=over 4

=item file => $file

A befunge program to be loaded for debug purposes.


=back



=head1 BUGS

Please report any bugs or feature requests to C<< <
language-befunge-debugger at rt.cpan.org> >>, or through the web
interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Language-Befunge-Debugger>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.



=head1 SEE ALSO

L<Language::Befunge>, L<POE>, L<Tk>.


Development is discussed on E<lt>language-befunge@mongueurs.netE<gt> -
feel free to join us.


You can also look for information on this module at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Language-Befunge-Debugger>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Language-Befunge-Debugger>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Language-Befunge-Debugger>

=back



=head1 AUTHOR

Jerome Quelin, C<< <jquelin at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright (c) 2007 Jerome Quelin, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=cut
