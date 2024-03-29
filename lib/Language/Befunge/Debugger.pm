#
# This file is part of Language::Befunge::Debugger.
# Copyright (c) 2007 Jerome Quelin, all rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#

package Language::Befunge::Debugger;

use strict;
use warnings;

use Language::Befunge;
use Language::Befunge::Debugger::Breakpoints;
use Language::Befunge::Vector;
use Readonly;
use Tk; # should come before POE
use Tk::Dialog;
use Tk::FBox;
use Tk::TableMatrix;
use Tk::ToolBar;
use POE;


our $VERSION = '0.3.6';

Readonly my $DECAY  => 8;
Readonly my $DELAY  => 0.1;
Readonly my @COLORS => ( [255,0,0], [0,0,255], [0,255,0], [255,255,0], [255,0,255], [0,255,255] );


#--
# constructor

#
# my $id = Language::Befunge::Debugger->spawn(%opts);
#
# create a new debugger gui for a befunge script. refer to the embedded
# pod for an explanation of the supported options.
#
sub spawn {
    my ($class, %opts) = @_;

    my $session = POE::Session->create(
        inline_states => {
            _start         => \&_on_start,
            # public events
            breakpoint_remove => \&_do_breakpoint_remove,
            # private events
            _breakpoint_add => \&_do_breakpoint_add,
            _open_file      => \&_do_open_file,
            # gui events
            _b_breakpoints => \&_on_b_breakpoints,
            _b_continue    => \&_on_b_continue,
            _b_forward     => \&_on_b_forward,
            _b_next        => \&_on_b_next,
            _b_open        => \&_on_b_open,
            _b_pause       => \&_on_b_pause,
            _b_quit        => \&_on_b_quit,
            _b_restart     => \&_on_b_restart,
            _tm_click      => \&_on_tm_click,
        },
        args => \%opts,
    );
    return $session->ID;
}


#--
# public events

#
# breakpoint_remove( $brkpt );
#
# remove $brkpt from the list of active breakpoints.
#
sub _do_breakpoint_remove {
    my ($k, $h, $brkpt) = @_[KERNEL, HEAP, ARG0];
    my ($type, $value) = split /: /, $brkpt;
    delete $h->{breakpoints}{$type}{$value}; # remove breakpoint
}


#--
# private events

#
# breakpoint_add( $brkpt );
#
# add $brkpt to the list of active breakpoints. request LDB::Breakpoints
# window to add it to its list.
#
sub _do_breakpoint_add {
    my ($k, $h, $args) = @_[KERNEL, HEAP, ARG0];
    my $brkpt = $args->[0];

    # store new breakpoint.
    my ($type, $value) = split /: /, $brkpt;
    $h->{breakpoints}{$type}{$value} = 1;

    # notify breakpoints window.
    if ( not exists $h->{w}{breakpoints} ) {
        my $id = Language::Befunge::Debugger::Breakpoints->spawn(
            parent     => $poe_main_window,
            breakpoint => $brkpt,
        );
        $h->{w}{breakpoints} = $id;
    } else {
        $k->post( $h->{w}{breakpoints}, 'breakpoint_add', $brkpt );
    }
}


#
# _open_file( $file );
#
# force reloading of $file, with everything that it implies - ie,
# reinitializes debugger state.
#
sub _do_open_file {
    my ($h, $file) = @_[HEAP, ARG0];

    # store filename
    $h->{file} = $file;

    # clean old ips
    foreach my $ip ( keys %{ $h->{ips} } ) {
        next unless defined $h->{ips}{$ip}{label};
        $h->{ips}{$ip}{label}->destroy;
        delete $h->{ips}{$ip}{label};
    }
    my $tm = $h->{w}{tm};
    $tm->tagDelete($_) for $tm->tagNames('decay-*');

    # load the new file
    my $bef = $h->{bef} = Language::Befunge->new({file=>$file});
    my $newip = Language::Befunge::IP->new($bef->get_dimensions);
    $bef->set_ips( [ $newip ] );
    $bef->set_retval(0);
    $h->{ips}      = {};
    $h->{tick}     = 0;
    $h->{continue} = 0;
    _create_ip_struct( $h, $newip );
    my $id = $newip->get_id;

    # force rescanning of the playfield
    $tm->configure(-command => sub { _get_cell_value($h->{bef}->get_storage,@_[1,2]) });
    $tm->tagCell("decay-$id-0", '0,0');
    _gui_set_pause($h);
}


#
# _on_start( \%opts );
#
# session initialization. %opts is received from spawn();
#
sub _on_start {
    my ($k, $h, $s, $opts) = @_[ KERNEL, HEAP, SESSION, ARG0 ];

    #-- load befunge file
    $k->yield( $opts->{file} ? ('_open_file', $opts->{file}) : '_b_open' );

    #-- create gui

    # prettyfying tk app.
    # see http://www.perltk.org/index.php?option=com_content&task=view&id=43&Itemid=37
    $poe_main_window->optionAdd('*BorderWidth' => 1);

    # menu
    $poe_main_window->optionAdd('*tearOff', 'false'); # no tear-off menus
    my $menuitems = [
        [ Cascade => '~File', -menuitems => [
            [ Button => '~Open',
                -command     => $s->postback('_b_open'),
                -accelerator => 'ctrl+o',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('fileopen16'),
                ],
            [ Separator => '' ],
            [ Button => '~Quit',
                -command     => $s->postback('_b_quit'),
                -accelerator => 'ctrl+q',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('actexit16'),
                ],
            ],
        ],
        [ Cascade => '~Run', -menuitems => [
            [ Button => '~Restart',
                -command     => $s->postback('_b_restart'),
                -accelerator => 'R',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('playstart16'),
                ],
            [ Button => '~Pause',
                -command     => $s->postback('_b_pause'),
                -accelerator => 'p',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('playpause16'),
                ],
            [ Button => '~Next',
                -command     => $s->postback('_b_next'),
                -accelerator => 'n',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('nav1rightarrow16'),
                ],
            [ Button => '~Continue',
                -command     => $s->postback('_b_continue'),
                -accelerator => 'c',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('nav2rightarrow16'),
                ],
            [ Button => 'Fast forward',
                -command     => $s->postback('_b_forward'),
                -accelerator => 'w',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('playend16'),
                ],
            [ Separator => '' ],
            [ Button => '~Breakpoints',
                -command     => $s->postback('_b_breakpoints'),
                #-accelerator => 'c',
                -compound    => 'left',
                -image       => $poe_main_window->Photo('calbell16'),
                ],
            ],
        ],
    ];
    my $menubar = $poe_main_window->Menu( -menuitems => $menuitems );
    $poe_main_window->configure( -menu => $menubar );
    $h->{w}{mnu_run} = $menubar->entrycget(1, '-menu');


    # toolbar
    my @tb = (
        [ 'Button', 'actexit16',        'quit',         '<Control-q>', '_b_quit'        ],
        [ 'Button', 'fileopen16',       'open',         '<Control-o>', '_b_open'        ],
        [ 'separator'                                                                   ],
        [ 'Button', 'calbell16',        'breakpoints',  '<F8>',        '_b_breakpoints' ],
        [ 'separator'                                                                   ],
        [ 'Button', 'playstart16',      'restart',      '<R>',         '_b_restart'     ],
        [ 'Button', 'playpause16',      'pause',        '<p>',         '_b_pause'       ],
        [ 'Button', 'nav1rightarrow16', 'next',         '<n>',         '_b_next'        ],
        [ 'Button', 'nav2rightarrow16', 'continue',     '<c>',         '_b_continue'    ],
        [ 'Button', 'playend16',        'fast forward', '<f>',         '_b_forward'     ],
    );
    my $tb = $poe_main_window->ToolBar(-movable=>0);
    foreach my $item ( @tb ) {
        my $type = shift @$item;
        $tb->separator( -movable => 0 ), next if $type eq 'separator';
        $h->{w}{$item->[3]} = $tb->$type(
            -image       => $item->[0],
            -tip         => $item->[1],
            -accelerator => $item->[2],
            -command     => $s->postback($item->[3]),
        );
    }
    $tb->separator(-movable => 0 );
    $h->{w}{ip} = $tb->LabEntry(-label=>'tick', -textvariable=>\$h->{tick},-justify=>'center',-state=>'readonly');

    # playfield
    my $fh1 = $poe_main_window->Frame->pack(-fill=>'both', -expand=>1);
    my $tm = $fh1->Scrolled( 'TableMatrix',
        -bg         => 'white',
        -scrollbars => 'osoe',
        -cols       => 200,
        -rows       => 999,
        -colwidth   => 3,
        -state      => 'disabled',
        -browsecmd  => $s->postback('_tm_click'),
    )->pack(-side=>'left', -fill=>'both', -expand=>1);
    $h->{w}{tm} = $tm;

    # frame with one summary label per running ip
    $h->{w}{f_ips} = $poe_main_window->Frame->pack(-fill=>'x');
}


#--
# gui events

#
# _b_breakpoints();
#
# called when the user wants to show/hide breakpoints.
#
sub _on_b_breakpoints {
    my ($k, $h) = @_[KERNEL, HEAP];

    return $k->post($h->{w}{breakpoints}, 'visibility_toggle')
        if exists $h->{w}{breakpoints};

    my $id = Language::Befunge::Debugger::Breakpoints->spawn(parent=>$poe_main_window);
    $h->{w}{breakpoints} = $id;
}


#
# _b_continue();
#
# called when the user wants the paused script to be ran.
#
sub _on_b_continue {
    my ($k, $h) = @_[KERNEL, HEAP];
    $h->{continue} = 1;
    _gui_set_continue($h);
    $k->yield('_b_next');
}


#
# _b_forward();
#
# called when the user wants the paused script to be ran as close as
# real time as possible.
#
sub _on_b_forward {
    my ($k, $h) = @_[KERNEL, HEAP];
    $h->{continue} = 2;
    _gui_set_continue($h);
    $k->yield('_b_next');
}

#
# _b_next();
#
# called when the user wants to advance the script one step further.
#
sub _on_b_next {
    my ($k,$h) = @_[KERNEL, HEAP];

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

    _create_ip_struct($h, $ip) unless exists $ips->{$ip};

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

    # fire again if user asked for continue.
    my $vec = $ip->get_position;
    my ($x, $y) = $vec->get_all_components;
    my $brkpts = $h->{breakpoints};
    my $is_breakpoint = exists $brkpts->{row}{$y}
        || exists $brkpts->{col}{$x}
        || exists $brkpts->{pos}{"$x,$y"};
    if ( $is_breakpoint ) {
        $k->yield('_b_pause');
    } else {
        $k->yield( '_b_next' ) if $h->{continue} == 2;
        $k->delay_set( '_b_next', $DELAY ) if $h->{continue} == 1;
    }
}


#
# _b_pause();
#
# called when the user wants the running script to be paused.
#
sub _on_b_pause {
    my ($k, $h) = @_[KERNEL, HEAP];
    $h->{continue} = 0;
    _gui_set_pause($h);
}


#
# _b_open();
#
# called when the user wants to load another befunge script.
#
sub _on_b_open {
    my @types = (
       [ 'Befunge scripts', '.bef' ],
       [ 'All files',       '*'    ]
    );
    # i know, this prevent poe from running
    my $file = $poe_main_window->getOpenFile(-filetypes => \@types);
    $_[KERNEL]->yield( '_open_file', $file )
        if defined($file) && $file ne '';
}


#
# _b_quit();
#
# called when the user wants to quit the application.
#
sub _on_b_quit {
    $poe_main_window->destroy;
}


#
# _b_restart();
#
# reload current file.
#
sub _on_b_restart {
    my ($k,$h) = @_[KERNEL, HEAP];
    $k->yield('_open_file', $h->{file});
}


#
# _tm_click();
#
# called when the user clicks on the field. used to add breakpoints.
#
sub _on_tm_click {
    my ($h, $s, $arg) = @_[HEAP, SESSION, ARG1];

    my ($old, $new) = @$arg;
    my ($x,$y) = split /,/, $new;

    #my $vec = Language::Befunge::Vector->new($y, $x);
    #my $val = $h->{bef}->get_torus->get_value($vec);
    #my $chr = chr $val;


    my $menuitems = [ [ Cascade => '~Add breakpoint', -menuitems => [
        [ Button=>"on ~row $x",      -command=>$s->postback('_breakpoint_add', "row: $x") ],
        [ Button=>"on ~col $y",      -command=>$s->postback('_breakpoint_add', "col: $y") ],
        [ Button=>"at ~pos ($y,$x)", -command=>$s->postback('_breakpoint_add', "pos: $y,$x") ],
    ] ] ];

    my $m = $poe_main_window->Menu( -menuitems => $menuitems );
    $m->Popup( -popover => 'cursor', -popanchor => 'nw' );
}


#--
# private subs


#
# _create_ip_struct( $heap, $ip );
#
# L::B::Debugger maintains some data associated to the running ips. this
# sub initialize the $heap data associated to a new $ip so it can be
# used later on.
#
# note: a new ip can be created either during befunge script loading, or
# when encountering the 't' command (thread) since L::B supports
# threaded befunge.
#
sub _create_ip_struct {
    my ($h, $ip) = @_;

    my $bef = $h->{bef};
    my $ips = $h->{ips};
    my $id  = $ip->get_id;
    my $w   = $h->{w};
    my $tm  = $w->{tm};

    # newly created ip - initializing data structure.
    $ips->{$ip}{object} = $ip;

    # - decay colors
    my ($r,$g,$b) = exists $COLORS[$id]
        ?  @{$COLORS[$id]}
        : (rand(255), rand(255), rand(255));

    foreach my $i ( 0 .. $DECAY-1 ) {
        my $ri = sprintf "%02x", $r + (255-$r) / $DECAY * ($i+1);
        my $gi = sprintf "%02x", $g + (255-$g) / $DECAY * ($i+1);
        my $bi = sprintf "%02x", $b + (255-$b) / $DECAY * ($i+1);
        $tm->tagConfigure( "decay-$id-$i", -bg => "#$ri$gi$bi" );
        $ips->{$ip}{bgcolor} = "#$ri$gi$bi" if $i == 0;
    }
    $w->{ip}->configure( -bg => $ips->{$ip}{bgcolor} );

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


#
# my $value = _get_cell_value( $storage, $row, $col );
#
# return the $value of $storage at the position ($row, $col). this
# function is used by Tk::TableMatrix to fill in the values of the
# cells.
#
sub _get_cell_value {
    my ($storage, $row, $col) = @_;
    my $v = Language::Befunge::Vector->new($col, $row);
    return $storage->get_char($v);
}


#
# _gui_set_continue( $heap );
#
# update the gui to enable/disable the buttons in order to match the
# state 'running'. it will use the $heap->{w} structure to find the
# wanted gui elements.
#
sub _gui_set_continue {
    my ($h) = @_;
    $h->{w}{_b_pause}   ->configure( -state => 'normal'   );
    $h->{w}{_b_next}    ->configure( -state => 'disabled' );
    $h->{w}{_b_continue}->configure( -state => 'disabled' );
    $h->{w}{_b_forward} ->configure( -state => 'disabled' );
    $h->{w}{mnu_run}->entryconfigure( 1, -state => 'normal'   );
    $h->{w}{mnu_run}->entryconfigure( 2, -state => 'disabled' );
    $h->{w}{mnu_run}->entryconfigure( 3, -state => 'disabled' );
}


#
# _gui_set_pause( $heap );
#
# update the gui to enable/disable the buttons in order to match the
# state 'paused'. it will use the $heap->{w} structure to find the
# wanted gui elements.
#
sub _gui_set_pause {
    my ($h) = @_;
    $h->{w}{_b_pause}   ->configure( -state => 'disabled' );
    $h->{w}{_b_next}    ->configure( -state => 'normal'   );
    $h->{w}{_b_continue}->configure( -state => 'normal'   );
    $h->{w}{_b_forward} ->configure( -state => 'normal'   );
    $h->{w}{mnu_run}->entryconfigure( 1, -state => 'disabled' );
    $h->{w}{mnu_run}->entryconfigure( 2, -state => 'normal'   );
    $h->{w}{mnu_run}->entryconfigure( 3, -state => 'normal'   );
}


#
# my $str = _ip_to_label( $ip, $bef );
#
# return a stringified value of the Language::Befunge::IP to be
# displayed in the label. it needs the Language::Befunge::Interpreter to
# fetch some values in the torus.
#
# the stringified value will be sthg like:
#   IP#2 @4,6 0 (ord=48) [ 32 111 52 32 ]
#
sub _ip_to_label {
    my ($ip,$bef) = @_;
    my $id     = $ip->get_id;
    my $vec    = $ip->get_position;
    my ($x,$y) = $vec->get_all_components;
    my $stack  = $ip->get_toss;
    my $val    = $bef->get_storage->get_value($vec);
    my $chr    = chr $val;
    return "IP#$id \@$x,$y $chr (ord=$val) [@$stack]";
}


#
# my $str = _vec_to_tablematrix_index( $vector );
#
# given a Language::Befunge::Vector object, return its stringified value
# as Tk::TableMatrix understand it: "x,y".
#
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

=head2 my $id = Language::Befunge::Debugger->spawn( %opts );

Create a graphical debugger, and return the associated POE session ID.
One can pass the following options:

=over 4

=item file => $file

A befunge program to be loaded for debug purposes.


=back



=head1 PUBLIC EVENTS

The POE session accepts the following events:


=over 4

=item breakpoint_remove( $brkpt )

Remove a breakpoint from the list of active breakpoints.


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

