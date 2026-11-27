' Starts J.A.R.V.I.S. without a console window flashing up: what the Start
' menu and desktop shortcuts (made by the setup) point at.
Dim fso, app
Set fso = CreateObject("Scripting.FileSystemObject")
app = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
CreateObject("WScript.Shell").Run "cmd.exe /c """ & app & "\start-jarvis.bat""", 0, False
