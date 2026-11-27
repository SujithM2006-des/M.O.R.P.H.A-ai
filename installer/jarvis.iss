; M.O.R.P.H.A. — Windows setup (Inno Setup 6).
;
; Built by installer\build.ps1, which stages the git-tracked files (never
; secrets or personal files) and passes:
;   /DAppVersion=2.0.0  /DStage=<staging folder>  /DOutDir=<where the .exe goes>
;
; The setup installs per user (no admin needed), shows the licence and
; copyright, lets the user pick the wake word and the offline mode, then runs
; installer\postinstall.ps1 - hidden, one step at a time under its own
; progress bar - for what a file copy cannot do (Node packages, Python, voice
; models, prerequisites).

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef Stage
  #define Stage "..\build-stage"
#endif
#ifndef OutDir
  #define OutDir "."
#endif

#define AppName "M.O.R.P.H.A."
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
; New installs in "MORPHA"; an existing one (from before the rename, in
; "JARVIS") is updated where it is: the setup reuses the folder it used.
DefaultDirName={autopf}\MORPHA
DefaultGroupName={#AppName}
; An install from before the rename used "J.A.R.V.I.S." for its Start menu
; folder: the new name is used, and the old entries go ([InstallDelete]).
UsePreviousGroup=no
AllowNoIcons=yes
; Per user only: M.O.R.P.H.A. writes into its own folder as it runs (its
; look files, the voice runtime it copies out of node_modules), which an
; all-users install in Program Files would not allow for a normal user.
PrivilegesRequired=lowest
LicenseFile={#Stage}\app\LICENSE
InfoBeforeFile={#Stage}\app\installer\BEFORE-YOU-INSTALL.txt
OutputDir={#OutDir}
OutputBaseFilename=MORPHA-Setup-{#AppVersion}
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
WelcomeLabel2=This will install [name/ver] on your computer.%n%n[name] is a personal AI assistant for Windows: talk to it ("Hey Morpha"), let it work on your PC, answer questions, set reminders, make videos and more - online, and offline too.%n%nCreated by Sujith M. Copyright (C) 2026 Sujith M.%nBased on the open-source JARVIS by Aditya Dewaskar.%n%nIt is recommended that you close other applications before continuing.

[Types]
Name: "standard"; Description: "Standard - online, with the ""Hey Morpha"" wake word"
Name: "full"; Description: "Full - also works offline (about 5 GB more to download, 9 GB on disk in all)"
Name: "minimal"; Description: "Minimal - online, no wake word"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "core"; Description: "M.O.R.P.H.A. (required)"; Types: standard full minimal custom; Flags: fixed
Name: "listener"; Description: """Hey Morpha"" wake word (about 350 MB to download)"; Types: standard full
Name: "offline"; Description: "Offline mode - voice commands and answers without the internet (about 5 GB to download)"; Types: full

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "jarvisswitch"; Description: "MORPHA ON / OFF switch (kill switch: turns M.O.R.P.H.A. and ""Hey Morpha"" on and off)"; GroupDescription: "Desktop switches:"; Components: listener
Name: "popupswitch"; Description: "MORPHA Popup ON / OFF switch (the small popup as his face, or the main window)"; GroupDescription: "Desktop switches:"
Name: "autostart"; Description: "Listen for ""Hey Morpha"" from Windows sign-in"; GroupDescription: "Startup:"; Components: listener

[Files]
Source: "{#Stage}\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Stage}\jarvis.ico"; DestDir: "{app}\installer"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Start M.O.R.P.H.A."
Name: "{group}\MORPHA ON - OFF switch"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\scripts\jarvis-switch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Turn M.O.R.P.H.A. and ""Hey Morpha"" on or off"; Components: listener
Name: "{group}\MORPHA Popup ON - OFF switch"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\scripts\popup-switch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "The small popup as M.O.R.P.H.A.'s face, or the main window"
; In Notepad: LICENSE has no extension and .md has no program on most PCs,
; so opening them directly asked "How do you want to open this file?".
Name: "{group}\Read me"; Filename: "{win}\notepad.exe"; Parameters: """{app}\README.md"""
Name: "{group}\License and copyright"; Filename: "{win}\notepad.exe"; Parameters: """{app}\LICENSE"""
Name: "{group}\Third-party notices"; Filename: "{app}\installer\THIRD-PARTY-NOTICES.txt"
Name: "{group}\Setup log"; Filename: "{app}\install-log.txt"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\installer\jarvis.ico"; Comment: "Start M.O.R.P.H.A."; Tasks: desktopicon

[Run]
; The set-up itself (postinstall.ps1) runs hidden from [Code] below, step by
; step under the setup's own progress bar: no console window.
Filename: "{sys}\wscript.exe"; Parameters: """{app}\installer\launch.vbs"""; Description: "Start {#AppName} now"; Flags: postinstall nowait skipifsilent

[InstallDelete]
; Shortcuts from before the rename (J.A.R.V.I.S. -> M.O.R.P.H.A.).
Type: filesandordirs; Name: "{userprograms}\J.A.R.V.I.S."
Type: files; Name: "{autodesktop}\J.A.R.V.I.S..lnk"

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
end;

var
  Problems: String;
  StepText: String;
  Keep: LongWord;

{ While a step runs, Setup disables its own window, and a disabled window
  ignores its title-bar buttons: Minimize did nothing. A timer keeps the
  window enabled (Cancel stays off), so it can be minimized as usual. }
function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: LongWord): LongWord; external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, uIDEvent: LongWord): Boolean; external 'KillTimer@user32.dll stdcall';
function EnableWindow(hWnd: HWND; bEnable: Boolean): Boolean; external 'EnableWindow@user32.dll stdcall';

procedure KeepMinimizable(H, Msg, IdEvent, Time: LongWord);
begin
  WizardForm.CancelButton.Enabled := False;
  EnableWindow(WizardForm.Handle, True);
end;

{ Each output line of the running step (hidden), shown under the step so a
  long step visibly moves: "Collecting pandas", "Downloading ...". }
procedure ShowLine(const S: String; const Error, FirstLine: Boolean);
var
  T: String;
  I: Integer;
begin
  T := Trim(S);
  for I := 1 to Length(T) do
    if Ord(T[I]) < 32 then T[I] := ' ';
  if T = '' then Exit;
  if Length(T) > 95 then T := Copy(T, 1, 92) + '...';
  WizardForm.FilenameLabel.Caption := StepText + '   ' + T;
end;

{ One postinstall.ps1 step, hidden (no window), under the progress bar. }
procedure RunStep(Step, Text: String; N, Total: Integer; Long: Boolean);
var
  Code: Integer;
  Results: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  WizardForm.StatusLabel.Caption := Text;
  StepText := 'Step ' + IntToStr(N) + ' of ' + IntToStr(Total) + ':';
  WizardForm.FilenameLabel.Caption := StepText;
  if Long then
    WizardForm.ProgressGauge.Style := npbstMarquee
  else
  begin
    WizardForm.ProgressGauge.Style := npbstNormal;
    WizardForm.ProgressGauge.Max := Total;
    WizardForm.ProgressGauge.Position := N - 1;
  end;
  Results := ExpandConstant('{tmp}\setup-results.txt');
  DeleteFile(Results);
  if not ExecAndLogOutput('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
              ExpandConstant('{app}\installer\postinstall.ps1') + '" -App "' + ExpandConstant('{app}') +
              '" -Only ' + Step + ' -Results "' + Results + '"' + SetupArgs(''),
              ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code, @ShowLine) then
    Problems := Problems + '- The "' + Step + '" step could not be started.' + #13#10
  else if LoadStringsFromFile(Results, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos('PROBLEM|', Lines[I]) = 1 then
        Problems := Problems + '- ' + Copy(Lines[I], 9, Length(Lines[I])) + #13#10;
  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Max := Total;
  WizardForm.ProgressGauge.Position := N;
end;

{ After the files are copied: what a file copy cannot do, one step at a time. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  Voice, Off: Boolean;
  N, Total: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  Problems := '';
  Voice := WizardIsComponentSelected('listener') or WizardIsComponentSelected('offline');
  Off := WizardIsComponentSelected('offline');
  Total := 6;
  if Voice then Total := Total + 1;
  if Off then Total := Total + 1;
  N := 1;
  Keep := SetTimer(0, 0, 250, CreateCallback(@KeepMinimizable));
  RunStep('Node', 'Checking Node.js (installing it if it is missing)...', N, Total, True); N := N + 1;
  RunStep('Chrome', 'Checking Google Chrome (installing it if it is missing)...', N, Total, True); N := N + 1;
  RunStep('Ffmpeg', 'Checking ffmpeg (installing it if it is missing)...', N, Total, True); N := N + 1;
  RunStep('Packages', 'Installing M.O.R.P.H.A. packages...', N, Total, True); N := N + 1;
  RunStep('Python', 'Setting up Python and its packages - this takes 5-15 minutes, please wait...', N, Total, True); N := N + 1;
  if Voice then begin RunStep('WakeModel', 'Downloading the "Hey Morpha" speech model...', N, Total, True); N := N + 1; end;
  if Off then begin RunStep('Offline', 'Downloading offline mode (Whisper and the offline AI model, about 3 GB)...', N, Total, True); N := N + 1; end;
  RunStep('Switches', 'Creating the desktop switches...', N, Total, False);
  KillTimer(0, Keep);
  WizardForm.StatusLabel.Caption := 'Done.';
  WizardForm.FilenameLabel.Caption := '';
end;

{ Finished: anything that needs fixing, in the setup window itself. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and (Problems <> '') then
    WizardForm.FinishedLabel.Caption := 'M.O.R.P.H.A. is installed, with some things to fix:' + #13#10#13#10 + Problems + #13#10 +
      'Fix them, then run the setup file again (it skips what is already done). Details: Start menu > M.O.R.P.H.A. > Setup log.';
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
      if MsgBox('M.O.R.P.H.A. has been removed, including its downloads (voice models, its Python, its Chrome logins).' + #13#10#13#10 +
                'Your memory and personal files are still kept in:' + #13#10 + Data + #13#10 +
                '(memory, profile, reminders, routines, history, AI keys) - so if you install M.O.R.P.H.A. again, it remembers you.' + #13#10#13#10 +
                'Delete them too?  Choose No to keep them.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Data, True, True, True);
  end;
end;
