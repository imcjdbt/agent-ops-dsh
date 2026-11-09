' DSH LIVE bridge launcher (no window).
' Kept next to bridge.mjs; path is resolved from this script's own folder,
' so it works even if the project lives under a non-ASCII path.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = here
sh.Run "cmd /c node bridge.mjs >> bridge.log 2>&1", 0, False
