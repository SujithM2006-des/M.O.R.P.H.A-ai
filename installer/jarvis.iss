; J.A.R.V.I.S. — Windows setup (Inno Setup 6).
;
; Built by installer\build.ps1, which stages the git-tracked files (never
; secrets or personal files) and passes:
;   /DAppVersion=2.0.0  /DStage=<staging folder>  /DOutDir=<where the .exe goes>
;
; The setup installs per user (no admin needed; "all users" can be chosen),
; shows the licence and copyright, lets the user pick the wake word and the
; offline mode, then runs installer\postinstall.ps1 for what a file copy
; cannot do (Node packages, Python, voice models, prerequisites).

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef Stage
  #define Stage "..\build-stage"
#endif
#ifndef OutDir
  #define OutDir "."
#endif

#define AppName "J.A.R.V.I.S."
#define Publisher "Sujith M"
#define AppUrl "https://github.com/SujithM2006-des/jarvisv2"

[Setup]
AppId={{8E2C6F4A-3B1D-4C7E-9A52-6D1F0B7E3A91}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
AppCopyright=Copyright (C) 2026 Sujith M. Based on JARVIS by Aditya Dewaskar. MIT License.
AppComments=Personal AI assistant for Windows, by Sujith M.
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#Publisher}
VersionInfoDescription={#AppName} Setup - personal AI assistant for Windows
VersionInfoCopyright=Copyright (C) 2026 Sujith M
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\JARVIS
DefaultGroupName={#AppName}
AllowNoIcons=yes
; Per user only: J.A.R.V.I.S. writes into its own folder as it runs (its
; look files, the voice runtime it copies out of node_modules), which an
; all-users install in Program Files would not allow for a normal user.
PrivilegesRequired=lowest
LicenseFile={#Stage}\app\LICENSE
InfoBeforeFile={#Stage}\app\installer\BEFORE-YOU-INSTALL.txt
OutputDir={#OutDir}
OutputBaseFilename=JARVIS-Setup-{#AppVersion}
SetupIconFile={#Stage}\jarvis.ico
UninstallDisplayIcon={app}\installer\jarvis.ico
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile={#Stage}\wizard.bmp
WizardSmallImageFile={#Stage}\wizard-small.bmp
Compression=lzma2/max
SolidCompression=yes
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This will install [name/ver] on your computer.%n%n[name] is a personal AI assistant for Windows: talk to it ("Hey Jarvis"), let it work on your PC, answer questions, set reminders, make videos and more - online, and offline too.%n%nCreated by Sujith M. Copyright (C) 2026 Sujith M.%nBased on the open-source JARVIS by Aditya Dewaskar.%n%nIt is recommended that you close other applications before continuing.

[Types]
Name: "standard"; Description: "Standard - online, with the ""Hey Jarvis"" wake word"
Name: "full"; Description: "Full - also works offline (about 5 GB more to download, 9 GB on disk in all)"
Name: "minimal"; Description: "Minimal - online, no wake word"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "core"; Description: "J.A.R.V.I.S. (required)"; Types: standard full minimal custom; Flags: fixed
Name: "listener"; Description: """Hey Jarvis"" wake word (about 200 MB to download)"; Types: standard full
Name: "offline"; Description: "Offline mode - voice commands and answers without the internet (about 5 GB to download)"; Types: full

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "jarvisswitch"; Description: "JARVIS ON / OFF switch (kill switch: turns J.A.R.V.I.S. and ""Hey Jarvis"" on and off)"; GroupDescription: "Desktop switches:"; Components: listener
Name: "popupswitch"; Description: "JARVIS Popup ON / OFF switch (the small popup as his face, or the main window)"; GroupDescription: "Desktop switches:"
Name: "autostart"; Description: "Listen for ""Hey Jarvis"" from Windows sign-in"; GroupDescription: "Startup:"; Components: listener

[Files]
Source: "{#Stage}\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Stage}\jarvis.ico"; DestDir: "{app}\installer"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Start J.A.R.V.I.S."
Name: "{group}\JARVIS ON - OFF switch"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\scripts\jarvis-switch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Turn J.A.R.V.I.S. and ""Hey Jarvis"" on or off"; Components: listener
Name: "{group}\JARVIS Popup ON - OFF switch"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\scripts\popup-switch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "The small popup as J.A.R.V.I.S.'s face, or the main window"
; In Notepad: LICENSE has no extension and .md has no program on most PCs,
; so opening them directly asked "How do you want to open this file?".
Name: "{group}\Read me"; Filename: "{win}\notepad.exe"; Parameters: """{app}\README.md"""
Name: "{group}\License and copyright"; Filename: "{win}\notepad.exe"; Parameters: """{app}\LICENSE"""
Name: "{group}\Third-party notices"; Filename: "{app}\installer\THIRD-PARTY-NOTICES.txt"
Name: "{group}\Setup log"; Filename: "{app}\install-log.txt"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Start J.A.R.V.I.S."; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\postinstall.ps1"" -App ""{app}""{code:SetupArgs}"; StatusMsg: "Setting up J.A.R.V.I.S. (prerequisites, packages, voice) - a window shows the progress. This can take a while..."; Flags: waituntilterminated
Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; Description: "Start {#AppName} now"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\uninstall.ps1"" -App ""{app}"""; Flags: runhidden waituntilterminated; RunOnceId: "StopJarvis"

[UninstallDelete]
; Made after install (npm, the first start), so not in the install record.
Type: filesandordirs; Name: "{app}\node_modules"
Type: filesandordirs; Name: "{app}\public\ort"
Type: filesandordirs; Name: "{app}\public\mediapipe"
Type: filesandordirs; Name: "{app}\dist"
Type: files; Name: "{app}\src\custom\CustomLayout.tsx"
Type: files; Name: "{app}\src\custom\custom-layout.css"
Type: files; Name: "{app}\src\custom\user-theme.css"
Type: files; Name: "{app}\install-log.txt"
Type: dirifempty; Name: "{app}\src\custom"
Type: dirifempty; Name: "{app}\src"
Type: dirifempty; Name: "{app}"

[Code]
{ What postinstall.ps1 sets up, from the components and tasks chosen. }
function SetupArgs(Param: String): String;
begin
  Result := '';
  if WizardIsComponentSelected('listener') then Result := Result + ' -Listener';
  if WizardIsComponentSelected('offline') then Result := Result + ' -Offline';
  if WizardIsTaskSelected('autostart') then Result := Result + ' -Autostart';
  if WizardIsTaskSelected('jarvisswitch') then Result := Result + ' -JarvisSwitch';
  if WizardIsTaskSelected('popupswitch') then Result := Result + ' -PopupSwitch';
  if WizardSilent then Result := Result + ' -NoPause';
end;

{ The user's settings and data are theirs: asked, and kept unless they say so. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Data := ExpandConstant('{%USERPROFILE}\.jarvis');
    if DirExists(Data) and (not UninstallSilent) then
      if MsgBox('Also delete your J.A.R.V.I.S. settings and data?' + #13#10#13#10 + Data + #13#10#13#10 +
                'This holds your profile, API keys, memory, reminders, routines and the downloaded voice models.' + #13#10 +
                'Choose No to keep them (for example, to reinstall later).',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Data, True, True, True);
  end;
end;
