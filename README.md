# PushRDPWrap
Remote RDPWrap Installer - RDP to a remote computer without kicking out the current user.

USAGE: MulRDP ComputerName
* ComputerName Needs to be a hostname, not an IP address (PSRemoting limitation)
  * In the future might add psexec fallback.
  * Script will enable PSRemoting on the remote computer automatically
* Obviously admin rights on the remote machine and network access to it are required.
* Local machine must be able to download files from github.

This script utilizes stascorp/rdpwrap and it's auto update script from asmtron/rdpwrap
The above tool allows concurrent RDP sessions, visit those repo pages for more details.

This script was created to resolve a problem I had for the following use case:
Sometimes I would need to RDP into a random computer in our domain to troubleshoot something.
The tools allowed me to do so without interrupting the user.
I also usually want to uninstall it after I'm done.

The problem was that I needed a reliable way to push this to a remote machine,
Including the tricky part of grabing an updated rdpwrap.ini file for the installed windows version that's required for this to work.

I used to copy the files from a local folder on my pc to the remote computer, and use psexec to launch autoupdate.bat
I had a relatively simple batch file for this, but there were a number of problems:

1. Sometimes one of the security clients installed on our computers would delete rdpwinst.exe.
2. Autoupdate.bat is occasionally updated with new URLs for .ini files so I want to grab the latest file.
3. At some point downloading files from github was blocked for most users so when running autoupdate.bat remotely, it failed to download files.

This script is my attempt to resolve this.
It will download rdpwrap, autoupdate, and all the .ini files from the URLs in autoupdate, copy those to the remote computer and install it.
It will wait for user input after patching RDP so you can have your session, and when done press ENTER to uninstall it.
