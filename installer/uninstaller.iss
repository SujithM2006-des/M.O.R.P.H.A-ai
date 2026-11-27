; J.A.R.V.I.S. — standalone uninstaller (Inno Setup 6): JARVIS-Uninstall.exe
;
; A small file to share next to the setup file. It removes J.A.R.V.I.S. from
; the PC — the copy JARVIS-Setup installed and any other J.A.R.V.I.S. folder
; (installer\remove-jarvis.ps1 does the work) — and keeps the user's memory
; and personal files, so a reinstall remembers them. It shows exactly what it
; found and will delete, and asks first.
;
; It installs nothing and never touches the setup file. It does not remove
; Node.js, Python, Chrome, ffmpeg or Ollama: other programs may use them.
;
;   JARVIS-Uninstall.exe              shows what it found, asks, then removes
;   JARVIS-Uninstall.exe /VERYSILENT  no questions (memory is still kept)

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

[Files]
; The work itself (installer\remove-jarvis.ps1): extracted to a temporary folder.
Source: "remove-jarvis.ps1"; Flags: dontcopy

[Code]
{ /SILENT or /VERYSILENT on the command line: no questions. }
function Quiet: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if (CompareText(ParamStr(I), '/SILENT') = 0) or (CompareText(ParamStr(I), '/VERYSILENT') = 0) then
      Result := True;
end;

{ remove-jarvis.ps1 in Scan or Remove mode; its report as lines. }
function RunScript(Mode: String; Show: Integer; var Lines: TArrayOfString): Boolean;
var
  Code: Integer;
  Report: String;
begin
  Report := ExpandConstant('{tmp}\report-' + Mode + '.txt');
  Result := Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\remove-jarvis.ps1') +
                 '" -Mode ' + Mode + ' -Report "' + Report + '"', '', Show, ewWaitUntilTerminated, Code)
            and LoadStringsFromFile(Report, Lines);
end;

{ "TYPE|value" -> value, for one TYPE (all of them, one per line). }
function Pick(Lines: TArrayOfString; Kind: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Lines) - 1 do
    if Pos(Kind + '|', Lines[I]) = 1 then
    begin
      if Result <> '' then Result := Result + #13#10;
      Result := Result + '   ' + Copy(Lines[I], Length(Kind) + 2, Length(Lines[I]));
    end;
end;

function InitializeSetup(): Boolean;
var
  Scan, Done: TArrayOfString;
  Installed, Copies, Kept, Msg, Summary: String;
  I: Integer;
begin
  { Nothing to show: this file does its job and closes. }
  Result := False;
  ExtractTemporaryFile('remove-jarvis.ps1');

  if not RunScript('Scan', SW_HIDE, Scan) then
  begin
    if not Quiet then MsgBox('Could not look for J.A.R.V.I.S. on this PC.', mbError, MB_OK);
    Exit;
  end;
  Installed := Pick(Scan, 'INSTALLED');
  Copies := Pick(Scan, 'COPY');
  Kept := Pick(Scan, 'DATA_KEEP');
  if (Installed = '') and (Copies = '') then
  begin
    if not Quiet then
      MsgBox('J.A.R.V.I.S. is not on this PC (for this Windows account), so there is nothing to remove.', mbInformation, MB_OK);
    Exit;
  end;

  if not Quiet then
  begin
    Msg := 'Remove J.A.R.V.I.S. from this PC?' + #13#10#13#10;
    if Installed <> '' then Msg := Msg + 'The installed J.A.R.V.I.S.:' + #13#10 + Installed + #13#10#13#10;
    if Copies <> '' then Msg := Msg + 'Other J.A.R.V.I.S. folders found (these whole folders are DELETED):' + #13#10 + Copies + #13#10#13#10;
    Msg := Msg + 'Also removed: the desktop switches, the "Hey Jarvis" sign-in entry, the Start menu entries, and ' +
           'J.A.R.V.I.S.''s downloads (voice models, its Python, its Chrome logins, logs).' + #13#10#13#10 +
           'KEPT, so a reinstall remembers you: your memory and personal files' + #13#10 +
           Kept + #13#10#13#10 +
           'Not touched: the J.A.R.V.I.S. setup file, your backups, and Node.js, Python, Chrome and the other programs it used.';
    if MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then Exit;
  end;

  { The window shows the progress. }
  RunScript('Remove', SW_SHOW, Done);
  if not Quiet then
  begin
    Summary := '';
    for I := 0 to GetArrayLength(Done) - 1 do Summary := Summary + Done[I] + #13#10;
    MsgBox('J.A.R.V.I.S. has been removed.' + #13#10#13#10 + Summary + #13#10 +
           'To install it again, run the J.A.R.V.I.S. setup file: it will remember you.', mbInformation, MB_OK);
  end;
end;
