# sort-media
Sort media files from cloud-storage sync-folder on PC onto local hard disc.

### Background
Media files such as photos and videos are often captured on mobile
devices and uploaded into cloud storage such as Dropbox and Google
Drive. These files will then be sync’ed into PC through the PC sync
app. The overall capacity is limited by the quota provided by the cloud
storage.

### Objective
This script is meant to be run as a cron job (e.g.: hourly) on the PC,
to move the media files that have sync’ed into the PC out of the sync
folder, and sort them into folders in local hard disc, named according
to date of the photos/videos taken. Hence, free-up the cloud storage
for more uploads.

### My Storage Flow
**Mobile** ==Dropbox==> **PC** ==Script==> **LocalHD** ==BackupSoftware==> **ExternamHD**

### Files Included
*sortMedia2Folder.pl - The actual script that perform the task.
*sortDropbox2MasterCopy.csh - A wrapper that simplify the call in the crontab.
*crontab - A sample crontab as example.
