; J.A.R.V.I.S. — standalone uninstaller (Inno Setup 6): JARVIS-Uninstall.exe
;
; A small file to share next to the setup file. It finds the J.A.R.V.I.S.
; that JARVIS-Setup installed (Windows' "Installed apps" record) and removes
; it with that install's own uninstaller: the program folder, the Start menu
; entries, both desktop switches, the "Hey Jarvis" sign-in entry and the
; record itself — asking before the user's settings and data go.
;
; It installs nothing and never touches the setup file. It does not remove
; Node.js, Python, Chrome, ffmpeg or Ollama: other programs may use them.
; If the install is broken (its uninstaller deleted), it cleans up itself.
;
;   JARVIS-Uninstall.exe              asks, then uninstalls
;   JARVIS-Uninstall.exe /VERYSILENT  no questions (the user's data is kept)

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
; The same AppId as jarvis.iss: that is how the install is found.
#define SetupAppId "{8E2C6F4A-3B1D-4C7E-9A52-6D1F0B7E3A91}"

[Setup]
AppId={{B7D41C2E-5F83-4A96-8E1B-3C9F0A6D2E57}
AppName={#AppName} Uninstaller
AppVersion={#AppVersion}
AppPublisher=Sujith M
AppCopyright=Copyright (C) 2026 Sujith M. MIT License.
VersionInfoVersion={#AppVersion}
VersionInfoCompany=Sujith M
VersionInfoDescription={#AppName} Uninstaller - removes J.A.R.V.I.S. from this PC
VersionInfoCopyright=Copyright (C) 2026 Sujith M
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
OutputDir={#OutDir}
OutputBaseFilename=JARVIS-Uninstall
SetupIconFile={#Stage}\jarvis.ico
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
DisableReadyPage=yes
DisableFinishedPage=yes
WizardStyle=modern
MinVersion=10.0

[Messages]
SetupAppTitle=J.A.R.V.I.S. Uninstaller
SetupWindowTitle=J.A.R.V.I.S. Uninstaller

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupAppId}_is1';

{ /SILENT or /VERYSILENT on the command line. }
function Quiet: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if (CompareText(ParamStr(I), '/SILENT') = 0) or (CompareText(ParamStr(I), '/VERYSILENT') = 0) then
      Result := True;
end;

{ The install's record, per user first (the setup installs per user). }
function ReadRecord(Name: String; var Value: String): Boolean;
begin
  Result := RegQueryStringValue(HKCU, UninstallKey, Name, Value);
  if not Result then
    Result := RegQueryStringValue(HKLM, UninstallKey, Name, Value);
end;

{ No working uninstaller left: what it would do, done here. }
procedure CleanUpBroken(Dir: String);
var
  Code: Integer;
  Group: String;
begin
  if FileExists(Dir + '\installer\uninstall.ps1') then
    Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + Dir + '\installer\uninstall.ps1" -App "' + Dir + '"',
         '', SW_HIDE, ewWaitUntilTerminated, Code);
  if (Dir <> '') and DirExists(Dir) then
    DelTree(Dir, True, True, True);
  Group := ExpandConstant('{userprograms}\J.A.R.V.I.S');
  if DirExists(Group) then
    DelTree(Group, True, True, True);
  RegDeleteKeyIncludingSubkeys(HKCU, UninstallKey);
end;

function InitializeSetup(): Boolean;
var
  Uninst, Dir, Args: String;
  Code: Integer;
begin
  { Nothing to show: this file does its job and closes. }
  Result := False;

  if not ReadRecord('UninstallString', Uninst) then
  begin
    if not Quiet then
      MsgBox('J.A.R.V.I.S. is not installed on this PC (for this Windows account), so there is nothing to remove.',
             mbInformation, MB_OK);
    Exit;
  end;
  Uninst := RemoveQuotes(Uninst);
  ReadRecord('InstallLocation', Dir);
  Dir := RemoveBackslashUnlessRoot(RemoveQuotes(Dir));

  if not Quiet then
    if MsgBox('Remove J.A.R.V.I.S. from this PC?' + #13#10#13#10 +
              'Installed in: ' + Dir + #13#10#13#10 +
              'This removes the program, its Start menu entries, the desktop switches and the "Hey Jarvis" sign-in entry. ' +
              'You will be asked whether to keep your settings and data.' + #13#10#13#10 +
              'Node.js, Python, Chrome and the other programs it uses are kept (other apps may need them). ' +
              'The J.A.R.V.I.S. setup file is not touched.',
              mbConfirmation, MB_YESNO) <> IDYES then
      Exit;

  if FileExists(Uninst) then
  begin
    if Quiet then Args := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' else Args := '';
    if not Exec(Uninst, Args, '', SW_SHOW, ewWaitUntilTerminated, Code) then
      CleanUpBroken(Dir);
  end
  else
  begin
    CleanUpBroken(Dir);
    if not Quiet then
      MsgBox('J.A.R.V.I.S. has been removed. (Its own uninstaller was missing, so the files were removed directly; your settings and data in ' +
             ExpandConstant('{%USERPROFILE}') + '\.jarvis were kept.)', mbInformation, MB_OK);
  end;
end;
