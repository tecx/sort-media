#!/usr/bin/perl

use strict;
use warnings;

use Carp;
use Getopt::Long;
use Pod::Usage;
use IO::Tee;
use File::Basename;
use File::Path;
use File::Spec;
use File::Type;
use File::stat;
use File::Copy;
use Time::localtime;
use Data::Dumper;
use Image::EXIF;

#===================================
#	Get Options
#===================================
&GetOptions (
	'src_folder=s'  => \my $opt_src,
	'dest_folder=s' => \my $opt_dest,
	'mode=s'        => \my $opt_mode,

	'logfile=s'     => \my $opt_logfile,
	'verbose'       => \my $opt_verbose,
	'help'          => \my $opt_help,
	'man'           => \my $opt_man,
) or confess "E: GetOptions error: $!\n";

&pod2usage(1)                        if $opt_help;
&pod2usage(-exitval=>0, -verbose=>2) if $opt_man;

my $runStat = {error=>0, warning=>0};

#===================================
#	LogFile
#===================================
$opt_logfile = basename($0, '.pl').'.log' unless ($opt_logfile);
mkpath dirname ($opt_logfile) unless (-d dirname ($opt_logfile));
open (my $LOG, ">$opt_logfile") or confess "E: Failed to write $opt_logfile: $!\n";
my $TEE = IO::Tee->new($LOG, \*STDOUT);
select($TEE);
*STDERR = *$TEE{IO};


if ($opt_src) {
	confess "E: Directory does not exist: $opt_src\n" unless (-e $opt_src);
	$opt_src = File::Spec->rel2abs($opt_src);
}
else {
	confess "E: 'src_folder' is a required input.\n";
}

if ($opt_dest) {
	mkpath $opt_dest unless (-f $opt_dest);
	$opt_dest = File::Spec->rel2abs($opt_dest);
}
else {
	confess "E: 'dest_folder' is a required input.\n";
}

if ($opt_mode) {
	confess "E: Invalid 'mode'. Acceptable values are: 'move' or 'copy'.\n" unless ($opt_mode =~ /^move$|^copy$/i);
	$opt_mode = lc $opt_mode;
}
else {
	confess "E: 'mode' is a required input.\n" unless ($opt_mode);
}

#===================================
#	Main
#===================================
my $H;
my $fileRead = 0;
my $fileSucc = 0;
my $fileFail = 0;

print "I: Parsing source folder: $opt_src\n";
opendir (SRC, $opt_src) or confess "E: Failed to read source folder: $!\n";
while (readdir SRC) {
	next if (/^\./);
	next if (/^Icon/);

	my $file = File::Spec->rel2abs("$opt_src/$_");
	print "I: Reading file: $file\n";
	$fileRead++;

	# Check file type
	my $fh = File::Type->new();
	$H->{$file}->{type} = $fh->mime_type($file);

	# Retry manually if failed to identify file type
	if (not defined $H->{$file}->{type} or
		$H->{$file}->{type} =~ /application\/octet-stream/) {
		if ($file =~ /\.mp4$|\.mov$/i) {
			$H->{$file}->{type}	= 'video';
			print "I:   File type: (Manual) $H->{$file}->{type}\n" if $opt_verbose;
		}
		elsif ($file =~ /\.jpe*g$|\.gif$|\.tiff*$|\.bmp$/i) {
			$H->{$file}->{type}	= 'image';
			print "I:   File type: (Manual) $H->{$file}->{type}\n" if $opt_verbose;
		}
		else {
			print "E:   Unsupported file type: $H->{$file}->{type}\n";
			$runStat->{error}++;
			&dropFile ($file);
			next;
		}
	}

	print "I:   File type: $H->{$file}->{type}\n" if $opt_verbose;

	# Get file info
	if ($H->{$file}->{type} =~ /image/) {
		my $exif = new Image::EXIF;
		$exif->file_name($file);
		my $allImgInfo = $exif->get_all_info();
		if ($exif->error) {
			print "W:   Failed to get image info: Image::EXIF::error $exif->errstr\n";
			$runStat->{warning}++;

			# Use file name date
			($H->{$file}->{year}, $H->{$file}->{date}) = useFileNameDate ($file);
			if ($H->{$file}->{year} < 0) {
				# Use stat file date (not accurate if upload date different from capture date)
				($H->{$file}->{year}, $H->{$file}->{date}) = useStatFileDate ($file);
				if ($H->{$file}->{year} < 0) {
					print "E:   Failed to get image date: stat(file)->ctime\n";
					$runStat->{error}++;
					&dropFile ($file);
					next;
				}
			}

			print "I:   Year=$H->{$file}->{year}  Date=$H->{$file}->{date}\n" if $opt_verbose;
		}
		else {
			my $date;
			my $time;
			if (defined $allImgInfo->{other}->{'Image Generated'}) {
				# Example: 'Image Generated' => '2014:11:04 12:48:52'
				($date, $time) = split (/\s+/, $allImgInfo->{other}->{'Image Generated'});
				$date =~ s/\://g;
				$H->{$file}->{date} = substr ($date, 2, 6);
				$H->{$file}->{year} = substr ($date, 0, 4);
				print "I:   Year=$H->{$file}->{year}  Date=$H->{$file}->{date}\n" if $opt_verbose;
			}
			else {
				print "W:   Failed to get image date: Image::EXIF::'other'::'Image Generated'\n";
				$runStat->{warning}++;

				($H->{$file}->{year}, $H->{$file}->{date}) = useStatFileDate ($file);
				if ($H->{$file}->{year} < 0) {
					print "E:   Failed to get image date: stat(file)->ctime\n";
					$runStat->{error}++;
					&dropFile ($file);
					next;
				}
				else {
					print "I:   Year=$H->{$file}->{year}  Date=$H->{$file}->{date}\n" if $opt_verbose;
				}
			}
		}
	}
	elsif ($H->{$file}->{type} =~ /video/) {
		# Use file name date
		($H->{$file}->{year}, $H->{$file}->{date}) = useFileNameDate ($file);
		if ($H->{$file}->{year} < 0) {
			# Use stat file date (not accurate if upload date different from capture date)
			($H->{$file}->{year}, $H->{$file}->{date}) = useStatFileDate ($file);
			if ($H->{$file}->{year} < 0) {
				print "E:   Failed to get image date: stat(file)->ctime\n";
				$runStat->{error}++;
				&dropFile ($file);
				next;
			}
		}

		print "I:   Year=$H->{$file}->{year}  Date=$H->{$file}->{date}\n" if $opt_verbose;
	}
	else {
		print "W:   Unsupported file type: $H->{$file}->{type}\n";
		$runStat->{warning}++;
		&dropFile ($file);
		next;
	}
}
close SRC;


# Make folders and move files
print "I: Preparing destination folders and start moving files...\n";
foreach my $srcFile (sort keys %{$H}) {
	# Source
	unless (-e $srcFile) {
		print "E: Missing source file: $srcFile\n";
		$runStat->{error}++;
		&dropFile ($srcFile);
		next;
	}

	# Destination
	my $yrPath = File::Spec->rel2abs("$opt_dest/$H->{$srcFile}->{year}");
	mkpath $yrPath unless (-e $yrPath);

	my $datePath = File::Spec->rel2abs("$yrPath/$H->{$srcFile}->{date}");
	mkpath $datePath unless (-e $datePath);

	my $destFile = "$datePath/" . basename($srcFile);
	if (-e $destFile) {
		print "I:   Destination file exist: $destFile\n";
		my $n = 0;
		do {
			$n++;
			$destFile =~ s/(\-\d+)*(\.[\d\w]+)$/\-${n}${2}/;
		} while (-e $destFile);
		print "I:   Renamed to: $destFile\n";
	}

	my $actWord = ($opt_mode=~/copy/i)? 'Copy' : 'Move';
	print "I: $actWord $srcFile to $destFile\n";

	if ($opt_mode eq 'copy') { copy $srcFile, $destFile; }
	else                     { move $srcFile, $destFile; }

	# Check if move success
	if (-e $destFile) {
		print "I:   Success!\n" if $opt_verbose;
		$fileSucc++;
	}
	else {
		print "E:   $actWord failed!\n";
		$runStat->{error}++;
		$fileFail++;
	}
}

print "\n";
printf "I: File Read    : %3d\n", $fileRead;
printf "I: File Success : %3d\n", $fileSucc;
printf "I: File Fail    : %3d\n", $fileFail;
print  "I: Completed.\n";


#===================================
#	Sub Routines
#===================================
sub dropFile {
	my $file = shift;
	print "W:   Drop file: $file\n";
	delete $H->{$file};
}

sub useStatFileDate {
	my $file   = shift;
	my $months = {Jan=>'01', Feb=>'02', Mar=>'03', Apr=>'04', May=>'05', Jun=>'06',
				  Jul=>'07', Aug=>'08', Sep=>'09', Oct=>'10', Nov=>'11', Dec=>'12'};

	# Example: Sat Dec 20 09:26:56 2014
	my ($dayword, $mon, $day, $time, $year) = split (/\s+/, ctime(stat($file)->ctime));

	my $date;
	if ($mon  =~ /\w+/ and
		$day  =~ /\d+/ and
		$year =~ /\d+/) {
		$date = substr($year, 2, 2) . $months->{$mon} . sprintf ("%.2d", $day);
	}
	else {
		return (-1, -1);
	}

	return ($year, $date);
}

sub useFileNameDate {
	my $file = shift;
	my $fname =  basename ($file);
	   $fname =~ s/\s.*//;

	my $y;
	my $m;
	my $d;
	my $date;

	# Example: 2015-01-03 02.32.06.jpeg
	if ($fname =~ /^(\d\d\d\d)\-(\d\d)\-(\d\d)/) {
		($y, $m, $d) = ($1, $2, $3);
		$date = substr($y, 2, 2) . $m . $d;
	}
	else {
		return (-1, -1);
	}

	return ($y, $date);
}

__END__

=head1 NAME

	sortMedia2Folder.pl

=head1 SYNOPSIS

	sortMedia2Folder.pl -src_folder PATH -dest_folder PATH

=head1 DESCRIPTION

	Sort media files from source folder into separate desination folders
	according to media date.

=head1 ARGUMENTS

=head2 Required:

	-src_folder  PATH  : Source folder containing media files.
	-dest_folder PATH  : Destination folder. Sub-folders named according to dates will be created.
	-mode <move|copy>  : Move or Copy source files to destination.

=head2 Optional:

	-logfile FILE      : Path to logfile. Default: $PWD/sortMedia2Folder.log

=head2 Example:

	sortMedia2Folder.pl -src_folder ~/Dropbox/Camera\ Uploads -dest_folder ~/Pictures/Master\ Copy

=head1 AUTHOR

	Teck-Siong Ong <ongtecksiong@gmail.com>

