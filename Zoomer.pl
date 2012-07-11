#!/usr/bin/perl -W
use strict;

use Gtk2 '-init';  
use Gtk2::GladeXML;

my $gladeXml = Gtk2::GladeXML->new("Zoomer.glade")
	or die "Glade file not found!";
$gladeXml->signal_autoconnect_from_package("Callbacks");

use Callbacks;
Callbacks::init($gladeXml);

Gtk2->main;


=head1 NAME

Image Zoomer

=head1 SYNOPSIS

 perl Zoomer.pl

=head1 DESCRIPTION

Creates a looping, perpetually zooming animated GIF file out of an image.
You can change the image size, zoom position and speed of the resulting animation.

=head1 OPTIONS

This is a GUI application. Only GTK command line switches apply.

=head1 LICENSE

Copyright (C) 2008 Jarrod Miller. All Rights Reserved.

This application is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Jarrod Miller <gigantic.midget@gmail.com>

=cut
