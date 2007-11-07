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
use Tk::ToolBar;
use POE;


our $VERSION = '0.2.0';
Readonly my $DECAY  => 8;
Readonly my @COLORS => ( [255,0,0], [0,0,255], [0,255,0], [255,255,0], [255,0,255], [0,255,255] );


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

    $h->{ips}    = {};
    $h->{tick}   = 0;

    #-- create gui

    # toolbar
    my @tb = (
        [ 'Button', 'actexit16',        'quit',     '<Control-q>', '_b_quit' ],
        [ 'Button', 'fileopen16',       'open',     '<Control-o>', '_b_open' ],
        [ 'separator' ],
        [ 'Button', 'playpause16',      'pause',    '<p>',         '_b_pause' ],
        [ 'Button', 'nav1rightarrow16', 'next',     '<n>',         '_b_next' ],
        [ 'Button', 'nav2rightarrow16', 'continue', '<c>',         '_b_continue' ],
    );
    my $tb = $poe_main_window->ToolBar(-movable=>0);
    foreach my $item ( @tb ) {
        my $type = shift @$item;
        $tb->separator( -movable => 0 ), next if $type eq 'separator';
        $tb->$type(
            -image       => $item->[0],
            -tip         => $item->[1],
            -accelerator => $item->[2],
            -command     => $s->postback($item->[3])
        );
    }
    $tb->separator(-movable => 0 );
    $h->{w}{ip} = $tb->LabEntry(-label=>'tick', -textvariable=>\$h->{tick},-justify=>'center',-state=>'readonly');

    #

    # playfield
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

    # frame with one summary label per running ip
    $h->{w}{f_ips} = $poe_main_window->Frame->pack(-fill=>'x');

    #-- various initializations
    #$tm->tagCell( 'current', '0,0' );
}

#--
# gui events

sub _on_b_next {
    my ($h) = $_[HEAP];

    my $w   = $h->{w};
    my $bef = $h->{bef};
    my $ips = $h->{ips};
    my $tm  = $h->{w}{tm};

    if ( scalar @{ $bef->get_ips } == 0 ) {
        # no more ip - end of program
        return;
    }

    # get next ip
    my $ip = shift @{ $bef->get_ips };
    my $id = $ip->get_id;

    if ( ! exists $ips->{$ip} ) {
        # newly created ip - initializing data structure.
        $ips->{$ip}{object} = $ip;

        # - decay colors
        my ($r,$g,$b) = exists $COLORS[$id] ?  @{$COLORS[$id]} : (rand(255), rand(255), rand(255));
        foreach my $i ( 0 .. $DECAY-1 ) {
            my $ri = sprintf "%02x", $r + (255-$r) / $DECAY * ($i+1);
            my $gi = sprintf "%02x", $g + (255-$g) / $DECAY * ($i+1);
            my $bi = sprintf "%02x", $b + (255-$b) / $DECAY * ($i+1);
            $tm->tagConfigure( "decay-$id-$i", -bg => "#$ri$gi$bi" );
            $ips->{$ip}{bgcolor} = "#$ri$gi$bi" if $i == 0;
        }

        # - summary label
        $ips->{$ip}{label} = $w->{f_ips}->Label(
            -text    => _ip_to_label($ip,$bef),
            -justify => 'left',
            -anchor  => 'w',
            -bg      => $ips->{$ip}{bgcolor},
        )->pack(-fill=>'x', -expand=>1);

        # - old positions
        $ips->{$ip}{oldpos} = [];
    }

    # show color of ip being currently processed
    $w->{ip}->configure(-bg=>$ips->{$ip}{bgcolor});

    # do some color decay.
    my $oldpos = $ips->{$ip}{oldpos};
    unshift @$oldpos, _vec_to_tablematrix_index($ip->get_position);
    pop     @$oldpos if scalar @$oldpos > $DECAY;
    foreach my $i ( reverse 0 .. $DECAY-1 ) {
        next unless exists $oldpos->[$i];
        $tm->tagCell("decay-$id-$i", $oldpos->[$i]);
    }



    # update gui

    # advance next ip
    $bef->set_curip($ip);
    $bef->process_ip;

    if ( $ip->get_end ) {
        # ip should be terminated - remove summary label.
        $ips->{$ip}{label}->destroy;
        delete $ips->{$ip}{label};
    } else {
        # update gui
        my $tmindex = _vec_to_tablematrix_index($ip->get_position);
        $tm->see($tmindex);
        $tm->tagCell( "decay-$id-0", $tmindex );
        $ips->{$ip}{label}->configure( -text => _ip_to_label($ip,$bef) );
    }


    # end of tick: no more ips to process
    if ( scalar @{ $bef->get_ips } == 0 ) {
        $h->{tick}++;
        $bef->set_ips( $bef->get_newips );
        $bef->set_newips( [] );

        # color decay on terminated ips
        my @ips    = map { $ips->{$_}{object} } keys %$ips;
        my @oldips = grep { $_->get_end } @ips;
        foreach my $oldip ( @oldips ) {
            my $oldid = $oldip->get_id;
            my $oldpos = $ips->{$oldip}{oldpos};
            pop @$oldpos;
            foreach my $i ( 0 .. $DECAY-1 ) {
                last unless exists $oldpos->[$i];
                my $decay = $i + $DECAY - scalar(@$oldpos);
                $tm->tagCell("decay-$oldid-$decay", $oldpos->[$i]);
            }
            delete $ips->{$oldip} unless scalar(@$oldpos);
        }
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

sub _ip_to_label {
    my ($ip,$bef) = @_;
    my $id     = $ip->get_id;
    my $vec    = $ip->get_position;
    my ($x,$y) = $vec->get_all_components;
    my $stack  = $ip->get_toss;
    my $val    = $bef->get_torus->get_value($vec);
    my $chr    = chr $val;
    return "IP#$id \@$x,$y $chr (ord=$val) [@$stack]";
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

