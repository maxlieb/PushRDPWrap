# TemservPatcher

A single-file PowerShell patcher for `termsrv.dll` that enables **concurrent RDP
sessions** on Windows — connect to a workstation or server over RDP without
kicking out the user who is already logged on.

This repo started life as `PushRDPWrap`, an installer around
[stascorp/rdpwrap](https://github.com/stascorp/rdpwrap). That approach was
complicated, needed an up-to-date `rdpwrap.ini` per Windows build, and kept
getting its files deleted by security agents (Cortex XDR, Defender). The
`termsrv.dll` patch is a much simpler, dependency-free replacement, based on
[fabianosrc/TermsrvPatcher](https://github.com/fabianosrc/TermsrvPatcher).

## What it does

- Detects the Windows version/build and selects the right byte pattern.
- Takes ownership of `termsrv.dll`, patches it, and swaps it in using a
  **kill-and-move** strategy that works even while the file is in use:
  the locked DLL is moved aside to a timestamped `.bak` and the patched copy
  is put in its place.
- Restores the original ACL and restarts `TermService` / `UmRdpService`.
- Self-elevates (re-launches as Administrator if needed).
- Idempotent: if the DLL already contains the patched bytes, it does nothing.

## Supported versions

| OS | Handling |
|----|----------|
| Windows 10 | single known pattern |
| Windows 11 (22H2 / 23H2 / 24H2 / 25H2 / **26H2**) | newest-first try-each |
| Windows Server 2016 / 2019 | single known pattern |
| Windows Server 2022 | single known pattern |
| Windows Server 2025 (build ≥ 26100) | newest-first try-each |

For Windows 11 and Server 2025+, the script tries each known byte pattern in
order (26H2/25H2 → 24H2 → 22H2/23H2) until one matches, so new feature-update
builds keep working without hard-coding exact `DisplayVersion` strings.

## Usage

Run it **as Administrator** on the target machine (it will self-elevate if you
don't):

```powershell
powershell -ExecutionPolicy Bypass -File .\TemservPatcher.ps1
```

It runs locally, with no arguments. To apply it remotely, push and run it with
whatever tool you already use — for example:

- **SCCM / ConfigMgr "Run Script"** — near real-time, and works even when the
  machine is off-LAN.
- **An RMM agent** (e.g. MeshCentral) — can both deliver and run the script.
- **PsExec** — `psexec \\HOST -s -c TemservPatcher.ps1`.

Then RDP in as you normally would, with your own client — the script does not
open an RDP session itself.

## Notes

- **Re-run after Windows updates.** A cumulative/feature update replaces
  `termsrv.dll` and reverts the patch; just run the script again.
- A timestamped backup (`termsrv.dll.<timestamp>.bak`) is left next to the
  original in `System32` each time a patch is applied.
- Enabling concurrent RDP sessions may have **licensing implications** in
  production/server environments — make sure it's appropriate for your use case.
- Patching a core system DLL is inherently invasive. Test on a representative
  machine for each new Windows build before relying on it in the field.

## Files

| File | Purpose |
|------|---------|
| `TemservPatcher.ps1` | The patcher. |
