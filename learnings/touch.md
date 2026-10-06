# Learning: touch — 2026-10-06
tags: windows,kiosk,rdp,gui-escape,mysql,udf,privesc,device-management

## Signal → vuln class (when you see X, pursue Y)
- kiosk/locked-down Windows with a GUI-only app, DeviceHub-style device management portal, MySQL as a service

## What worked (the insight, generalized — NOT box-specific steps)
- unauth /api/status leaked serial -> portal password; dashboard + device APIs leaked device creds; /sec:rdp got the kiosk session; scanner power-off + /api/scan produced a native WinForms error dialog whose support URL opened Edge; Ctrl+S -> Save As -> filename 'cmd' -> cmd.exe; backend source leaked a hardcoded DB password fallback; a maintenance .bat held the MySQL root password in plaintext; writable MySQL plugin_dir + LocalSystem service + self-compiled 64-bit UDF = SYSTEM

## Dead-ends (don't waste time here next time)
- RDP +auth-only and netexec both false-negatived while full sessions worked; \\tsclient drive redirection never resolved; FreeRDP pipe: mangles long writes (push logic into a downloaded .bat); sqlmap's packaged lib_mysqludf_sys.dll_ is not a loadable PE (errno 193); MySQL caches plugin DLLs by filename so a failed load poisons that name; Ctrl+C to a kiosk console aborts the launcher batch and wedges it on 'Terminate batch job (Y/N)?'

## CVE / technique refs
- —
