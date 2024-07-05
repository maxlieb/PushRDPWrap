# Edit
This was a fun project, but it has a couple of problems:
* What if the computer is not reachable by LAN?
* It still has some issues with security agents (Cortex XDR for example)...
* Complicated and therefore unreliable.

Found a much simpler solution:
https://github.com/fabianosrc/TermsrvPatcher

I't a universal termsrv.dll patcher, that:
* Consists of a single, short, and simple to understand PowerShell script.
* Has no external dependencies.
* Doesn't need updating (though still needs to be rerun after windows updates)
* Doesn't seem to cause troubles with security agents. (Cortex XDR & Win Defender at least)

Asuming github is not filtered,
You can even download and run the patcher localy or remotely (add -computername parameter) using this PowerShell one-liner
Invoke-Expression (Invoke-WebRequest https://raw.githubusercontent.com/fabianosrc/TermsrvPatcher/main/TermsrvPatcher.ps1 -UseBasicParsing).content

If github is filtered just copy the script, once you get it onto the disk it works offline.

Other ideas I used it with:
Run it using SCCM's 'run script' feature - that allows me to execute it almost in realtime and even of the computer is not on LAN.
Once done I can RDP into it.
if Off LAN I can do it using some RMM solution, MeshCentral for example, which can also technically run the script in the first place.


# PushRDPWrap
Remote RDPWrap Installer - Connect using RDP to workstations without kicking out the current user.

USAGE: MulRDP ComputerName
* ComputerName Needs to be a hostname, not an IP address (PSRemoting limitation)
  * In the future might add psexec fallback.
  * Script will enable PSRemoting on the remote computer automatically.
* Obviously admin rights on the remote machine, and network access to it, are required.
* Local machine must be able to download files from github.
* It does NOT create an RDP session, do this manually like you normally would, using whatever app and device you like.

This script utilizes [stascorp/rdpwrap](https://github.com/stascorp/rdpwrap) and it's auto update script from [asmtron/rdpwrap](https://github.com/stascorp/rdpwrap/pull/1160).

The above tool allow concurrent RDP sessions, visit the links for more details.

This script was created to resolve a problem I had for the following use case:

Sometimes I would need to RDP into a random computer in our domain to troubleshoot something.
The tool allowed me to do so without interrupting the user.

I also usually want to uninstall it after I'm done.

The problem was that I needed a reliable way to push this to a remote machine,
Including the tricky part of grabing an updated rdpwrap.ini file for the installed windows version that's required for this to work.

I used to copy the files from a local folder on my pc to the remote computer, and use psexec to launch autoupdate.bat

I had a relatively simple batch file for this, but there were a number of problems:

1. Sometimes one of the security clients would delete rdpwinst.exe.
2. Autoupdate.bat is occasionally updated with new URLs for .ini files so I want to grab the latest file.
3. At some point downloading files from github was blocked for most users, so when running autoupdate.bat remotely, it failed to download files.

This script is my attempt to resolve this.

It will locally download rdpwrap, autoupdate, and all the .ini files from the URLs in autoupdate.bat, copy those to the remote computer and install it.

It will wait for user input after patching RDP, so you can have your session,
and when done return to the command prompt, and press ENTER to uninstall it.
