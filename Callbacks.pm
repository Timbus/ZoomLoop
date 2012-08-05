#!/usr/bin/perl
use strict;

package Callbacks;
use Image::Magick;

#This will be our cheap-ass 'Model'.
our %data = (
	srcimg       => undef,
	imgsize      => [ 0, 0 ],
	zoomcenter   => [ 0, 0 ],
	startsize    => 0,
	interval     => 0,
	framecount   => 1,
	currentframe => 1,
	changed      => 0,
	rotation     => 0,
	renders      => undef,
);
#This prevents any coder errors. Key typos and such.
use Hash::Util 'lock_keys';
lock_keys(%data);

#This is our 'view'.
my $gladeXml;

sub init {
	$gladeXml = shift
	  or die "No glade XML file passed to the callback init";

	#Make the image box a drop target for files.
	$gladeXml->get_widget("ebLoaded")
	  ->drag_dest_set( "GTK_DEST_DEFAULT_ALL", "GDK_ACTION_COPY" );

	#Apparently files are URIs, I guess..
	$gladeXml->get_widget("ebLoaded")->drag_dest_add_uri_targets();

	#Set the data hash to some of the glade-defined defaults
	#(Is this is proper programming practice?? Probably not.)
	$data{'startsize'}  = $gladeXml->get_widget("spStartWidth")->get_value;
	$data{'interval'}   = $gladeXml->get_widget("spInterval")->get_value;
	$data{'framecount'} = $gladeXml->get_widget("spGifFrames")->get_value;
	$data{'rotation'}   = $gladeXml->get_widget("spRotation")->get_value;

	$data{'renders'} = Image::Magick->new;
}

sub on_bnLoadImage_clicked {
	#Bring up a filechooser dialog.
	my $fileChooser = Gtk2::FileChooserDialog->new(
		'Load an image',
		undef,
		'open',
		'gtk-cancel' => 'cancel',
		'gtk-ok'     => 'ok'
	);

	#Filter images.
	my $filter = Gtk2::FileFilter->new();
	$filter->set_name("Images");
	$filter->add_mime_type("image/*");
	$fileChooser->add_filter($filter);

	#Get selected image name
	my $fileName = do {
		$fileChooser->get_filename if $fileChooser->run eq 'ok';
	};
	$fileChooser->destroy;

	load_image($fileName) if $fileName;
}

sub on_ebLoaded_drag_data_received {

	#Data is in position 4 of the arg array. The rest is irrelevant.
	my $dragdata = $_[4];

	my $fileName = $dragdata->get_uris;
	$fileName =~ s|^file:/+|/|i;

	load_image($fileName);
}

sub load_image {
	my $fileName = shift or die "No image name passed to load_image";

	my $img = Image::Magick->new;
	my $err = $img->Read($fileName);
	die $err if $err;

	$data{'srcimg'} = $img->[0];
	my ( $x, $y ) = $img->Get( 'width', 'height' );
	$data{'imgsize'} = [ $x, $y ];
	$data{'zoomcenter'} = [ int $x / 2, int $y / 2 ];
	$data{'changed'} = 1;

	$gladeXml->get_widget("sclFrameSelect")->set_sensitive(1);
	$gladeXml->get_widget("bnSaveGif")->set_sensitive(1);
	$gladeXml->get_widget("bnCloseImage")->set_sensitive(1);

	$gladeXml->get_widget("spWidth")->set_value($x);
	$gladeXml->get_widget("spHeight")->set_value($y);

	update_image();

	$gladeXml->get_widget("MainWindow")->resize( 1, 1 );
}

sub on_bnCloseImage_clicked {
	$gladeXml->get_widget("imgLoaded")
	  ->set_from_stock( 'gtk-orientation-portrait', 'dialog' );

	$gladeXml->get_widget("sclFrameSelect")->set_sensitive(0);
	$gladeXml->get_widget("bnSaveGif")->set_sensitive(0);
	$gladeXml->get_widget("bnCloseImage")->set_sensitive(0);

	$data{'srcimg'} = undef;
	@{ $data{'renders'} } = ();

	$gladeXml->get_widget("MainWindow")->resize( 1, 1 );
}

sub on_bnSaveGif_clicked {

	#Pop up a save dialog.
	my $fileChooser = Gtk2::FileChooserDialog->new(
		'Save image as...',
		undef,
		'save',
		'gtk-cancel' => 'cancel',
		'gtk-ok'     => 'ok'
	);
	my $filter = Gtk2::FileFilter->new();
	$filter->set_name("Images");
	$filter->add_mime_type("image/gif");
	$fileChooser->add_filter($filter);

	$fileChooser->set_do_overwrite_confirmation(1);
	$fileChooser->set_current_name("zoom.gif");

	#Quit if they hit cancel, otherwise assign the name to $fileName
	my $fileName = do {
		return $fileChooser->destroy if $fileChooser->run ne 'ok';
		$fileChooser->get_filename;
	};

	#Get each frame to be written
	render_frame($_) for 1 .. $data{framecount};
	
	#Using globals like this is bad programming practice.
	#But its more efficient.
	$data{'renders'}->Set(
		delay => $data{'interval'},
		loop  => 0
	);
	my $x = $data{'renders'}->Write($fileName);

	$fileChooser->destroy;

	die $x if $x;
}

sub on_ebLoaded_button_press_event {
	return unless $data{'srcimg'};
	my ( $eb, $event ) = @_;

	#Get the position clicked relative to the image.
	$data{'zoomcenter'} = do {
		my ( $x, $y ) = ( $event->x, $event->y );    #;;;
		$x -= int( ( $eb->allocation->width - $data{'imgsize'}[0] ) / 2 )
		  if ( $data{'imgsize'}[0] < $eb->allocation->width );
		$y -= int( ( $eb->allocation->height - $data{'imgsize'}[1] ) / 2 )
		  if ( $data{'imgsize'}[1] < $eb->allocation->height );

		#Make sure no values are < 0
		[ $x < 0 ? 0 : $x, $y < 0 ? 0 : $y ];
	};

	$data{'changed'} = 1;
	update_image();
}

sub on_spGifFrames_value_changed {
	my $w = shift;
	$data{framecount} = $w->get_value;

	#Fix up the frame selection scale
	my $scl = $gladeXml->get_widget("sclFrameSelect");
	$scl->set_range( 1, $w->get_value );
	$data{'currentframe'} = $scl->get_value;
	$data{'changed'}      = 1;

	update_image();
}

sub on_spInterval_value_changed {
	$data{'interval'} = shift->get_value;
}

sub on_spWidth_value_changed {
	my $w = shift->get_value;
	return if $data{'imgsize'}[0] == $w;
	$data{'imgsize'}[0] = $w;

	$data{'changed'} = 1;
	update_image();

	$gladeXml->get_widget("MainWindow")->resize( 1, 1 );
}

sub on_spHeight_value_changed {
	my $w = shift->get_value;
	return if $data{'imgsize'}[1] == $w;
	$data{'imgsize'}[1] = $w;

	$data{'changed'} = 1;
	update_image();

	$gladeXml->get_widget("MainWindow")->resize( 1, 1 );
}

sub on_spStartWidth_value_changed {
	$data{'startsize'} = shift->get_value;
	$data{'changed'}   = 1;
	update_image();
}

#sub on_spRotation_value_changed {
#	$data{'rotation'} = shift->get_value;
#	$data{'changed'}  = 1;
#	update_image();
#}

sub on_sclFrameSelect_value_changed {
	$data{'currentframe'} = shift->get_value;
	update_image();
}

sub update_image {

	#No image? Don't update.
	return unless $data{'srcimg'};

	#Render the image, get its blob.
	my $blob =
	  render_frame( $data{'currentframe'} )->ImageToBlob( magick => 'jpg' );
	$blob || die "ImageToBlob failed";

	#Convert to pixbuf using a pixbufloader
	my $pbf = Gtk2::Gdk::PixbufLoader->new;
	$pbf->write($blob);
	$pbf->close;

	#Set the display.
	$gladeXml->get_widget("imgLoaded")->set_from_pixbuf( $pbf->get_pixbuf );
}

sub render_frame {
	my $frame = shift or die "No frame specified to render";
	$frame -= 1;

	if ( !$data{'changed'} ) {
		return $data{'renders'}->[$frame] if $data{'renders'}->[$frame];
	}
	else {
		@{ $data{'renders'} } = ();
		$data{'changed'} = 0;
	}

	#Couple of fast access vars.
	my ( $ptX, $ptY ) = @{ $data{'zoomcenter'} };
	my ( $szX, $szY ) = @{ $data{'imgsize'} };

	#Create the canvas.
	my $img = Image::Magick->new;
	$img->Set( size => $data{'imgsize'}[0] . 'x' . $data{'imgsize'}[1], );
	$img->Read('xc:white');

	#Calculate a few scale settings
	my $scaleRatio = $szX / $data{'startsize'};
	my $scale      = ( $scaleRatio**( 1 / $data{'framecount'} ) )**$frame;

	#$scale = $scale * $scaleRatio;

	#Start at the large image and loop down.
	while ( $szX * $scale > 1.6 ) {

		#Get the source image. Resize if needed 
		#(Argh perltidy stop making this look so ugly, arg I give up)
		my $srcimg = do {
			if (   $data{'srcimg'}->Get('width') == $szX
				&& $data{'srcimg'}->Get('height') == $szY )
			{
				$data{'srcimg'}->Clone;
			}
			else {
				my $t = $data{'srcimg'}->Clone;
				$t->Resize(
					width  => $data{'imgsize'}[0],
					height => $data{'imgsize'}[1],
					filter => 'Cubic'
				);
				$t;
			}
		};

		if ( $scale >= 1 ) {

			#Cut away the parts we don't need, then scale back to fullsize
			$srcimg->Crop(
				'x'    => $ptX - $ptX / $scale,
				'y'    => $ptY - $ptY / $scale,
				width  => $szX / $scale,
				height => $szY / $scale,
			) if $scale > 1;

			$srcimg->Resize( width => $szX, height => $szY ) if $scale > 1;

			$img->Composite(
				image   => $srcimg,
				compose => 'Atop',
			);
		}
		else {
			$srcimg->Resize( width => $scale * $szX, height => $scale * $szY );

			$img->Composite(
				image   => $srcimg,
				compose => 'Atop',
				'x'     => $ptX - $ptX * $scale,
				'y'     => $ptY - $ptY * $scale,
			);
		}

		$scale /= $scaleRatio;
	}

	#Add image to the cache.
	$data{'renders'}->[$frame] = $img;
	return $img;
}

#Standard gtk exit stuff
sub on_MainWindow_destroy { Gtk2->main_quit }
sub gtk_main_quit         { Gtk2->main_quit }

1;
