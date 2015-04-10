#!/bin/csh
# Dropbox Camera Upload Folder to Archive (Master Copy)
$HOME/scripts/sortMedia2Folder.pl \
	-verbose -mode move \
	-src_folder	 $HOME/Dropbox/Camera\ Uploads \
	-dest_folder $HOME/Pictures/Master\ Copy   \
	-logfile /tmp/sortDropbox2MasterCopy.my_cam.log
