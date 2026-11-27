; M.O.R.P.H.A. — standalone uninstaller (Inno Setup 6): MORPHA-Uninstall.exe
;
; A small file to share next to the setup file. It removes M.O.R.P.H.A. from
; the PC — the copy MORPHA-Setup installed and any other M.O.R.P.H.A. folder
; (installer\remove-jarvis.ps1 does the work, hidden) — and keeps the user's
; memory and personal files, so a reinstall remembers them.
;
; It looks like any Windows uninstaller: Welcome, "Ready to Uninstall" with
; the list of what goes and what stays, a progress bar, and Finished. No
; console window. It installs nothing and never touches the setup file, and
; keeps Node.js, Python, Chrome, ffmpeg and Ollama (other programs use them).
;
;   MORPHA-Uninstall.exe              the wizard
;   MORPHA-Uninstall.exe /SILENT      just the progress bar
;   MORPHA-Uninstall.exe /VERYSILENT  nothing shown (memory is still kept)

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

[Setup]
AppId={{B7D41C2E-5F83-4A96-8E1B-3C9F0A6D2E57}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Sujith M
AppCopyright=Copyright (C) 2026 Sujith M. MIT License.
VersionInfoVersion={#AppVersion}
VersionInfoCompany=Sujith M
VersionInfoDescription={#AppName} Uninstaller - removes M.O.R.P.H.A. from this PC
VersionInfoCopyright=Copyright (C) 2026 Sujith M
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
OutputDir={#OutDir}
OutputBaseFilename=MORPHA-Uninstall
SetupIconFile={#Stage}\jarvis.ico
WizardImageFile={#Stage}\wizard.bmp
WizardSmallImageFile={#Stage}\wizard-small.bmp
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableReadyPage=no
DisableFinishedPage=no
WizardStyle=modern
MinVersion=10.0

[Files]
; The work itself (installer\remove-jarvis.ps1): extracted to a temporary folder, run hidden.
Source: "remove-jarvis.ps1"; Flags: dontcopy

[Messages]
SetupAppTitle=Uninstall M.O.R.P.H.A.
SetupWindowTitle=Uninstall M.O.R.P.H.A.
WelcomeLabel1=Uninstall M.O.R.P.H.A.
WelcomeLabel2=This will remove M.O.R.P.H.A. from your computer.%n%nYour memory and personal files are kept, so if you install M.O.R.P.H.A. again, it remembers you.%n%nThe M.O.R.P.H.A. setup file is not touched.%n%nClick Next to see what will be removed.
WizardReady=Ready to Uninstall
ReadyLabel1=M.O.R.P.H.A. is ready to be removed from your computer.
ReadyLabel2a=Click Uninstall to remove it, or click Back to review.
ReadyLabel2b=Click Uninstall to remove it, or click Back to review.
ButtonInstall=&Uninstall
WizardInstalling=Uninstalling
InstallingLabel=Please wait while M.O.R.P.H.A. is removed from your computer.
FinishedHeadingLabel=M.O.R.P.H.A. has been removed
FinishedLabelNoIcons=M.O.R.P.H.A. was removed from your computer.
ClickFinish=Click Finish to close.
ExitSetupTitle=Exit Uninstall
ExitSetupMessage=M.O.R.P.H.A. has not been removed.%n%nExit the uninstaller?

[Code]
var
  Scan: TArrayOfString;
  Done: String;
  Keep: LongWord;

{ While a step runs, Setup disables its own window, and a disabled window
  ignores its title-bar buttons: Minimize did nothing. A timer keeps the
  window enabled (Cancel stays off: no stopping half-way), so it can be
  minimized as usual. }
function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: LongWord): LongWord; external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, uIDEvent: LongWord): Boolean; external 'KillTimer@user32.dll stdcall';
function EnableWindow(hWnd: HWND; bEnable: Boolean): Boolean; external 'EnableWindow@user32.dll stdcall';

procedure KeepMinimizable(H, Msg, IdEvent, Time: LongWord);
begin
  WizardForm.CancelButton.Enabled := False;
  EnableWindow(WizardForm.Handle, True);
end;

{ remove-jarvis.ps1, hidden: Scan, or one Remove step. Its report as lines. }
function RunScript(Args: String; var Lines: TArrayOfString): Boolean;
var
  Code: Integer;
  Report: String;
begin
  Report := ExpandConstant('{tmp}\report.txt');
  DeleteFile(Report);
  Result := Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
                 ExpandConstant('{tmp}\remove-jarvis.ps1') + '" ' + Args + ' -Report "' + Report + '"',
                 '', SW_HIDE, ewWaitUntilTerminated, Code)
            and LoadStringsFromFile(Report, Lines);
end;

{ The values of one "TYPE|value" kind in the scan, joined with Sep. }
function Pick(Kind, Prefix, Sep: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Scan) - 1 do
    if Pos(Kind + '|', Scan[I]) = 1 then
    begin
      if Result <> '' then Result := Result + Sep;
      Result := Result + Prefix + Copy(Scan[I], Length(Kind) + 2, Length(Scan[I]));
    end;
end;

function InitializeSetup(): Boolean;
begin
  ExtractTemporaryFile('remove-jarvis.ps1');
  Result := RunScript('-Mode Scan', Scan) and ((Pick('INSTALLED', '', '') <> '') or (Pick('COPY', '', '') <> ''));
  if not Result then
    if not WizardSilent then
      MsgBox('M.O.R.P.H.A. is not on this computer (for this Windows account), so there is nothing to remove.', mbInformation, MB_OK);
end;

{ "Ready to Uninstall": what goes and what stays. }
function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  S: String;
begin
  S := 'Will be removed:' + NewLine;
  if Pick('INSTALLED', '', '') <> '' then S := S + Space + 'M.O.R.P.H.A. installed in ' + Pick('INSTALLED', '', '') + NewLine;
  if Pick('COPY', '', '') <> '' then S := S + Pick('COPY', Space + 'the M.O.R.P.H.A. folder ', NewLine) + NewLine;
  S := S + Space + 'the desktop switches and the "Hey Morpha" sign-in entry' + NewLine +
           Space + 'the Start menu entries' + NewLine +
           Space + 'M.O.R.P.H.A.''s downloads: voice models, its Python, its Chrome logins, logs' + NewLine + NewLine +
       'Kept (so a reinstall remembers you):' + NewLine +
           Space + 'your memory and personal files: ' + Pick('DATA_KEEP', '', '') + NewLine + NewLine +
       'Not touched:' + NewLine +
           Space + 'the M.O.R.P.H.A. setup file and your backups' + NewLine +
           Space + 'Node.js, Python, Chrome, ffmpeg and Ollama (other programs may use them)';
  Result := S;
end;

procedure Progress(Step, Steps: Integer; Text: String);
begin
  WizardForm.StatusLabel.Caption := Text;
  WizardForm.FilenameLabel.Caption := '';
  WizardForm.ProgressGauge.Max := Steps;
  WizardForm.ProgressGauge.Position := Step;
end;

{ The work, step by step under the progress bar. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  Lines: TArrayOfString;
  Copies, Common: String;
  I, N: Integer;
begin
  if CurStep <> ssInstall then Exit;
  Copies := Pick('COPY', '', '|');
  Common := ' -Mode Remove -Copies "' + Copies + '"';
  Done := '';
  N := 5;
  Keep := SetTimer(0, 0, 250, CreateCallback(@KeepMinimizable));
  Progress(0, N, 'Stopping M.O.R.P.H.A....');
  RunScript(Common + ' -Only Stop', Lines);
  Progress(1, N, 'Removing the installed M.O.R.P.H.A....');
  RunScript(Common + ' -Only Installed', Lines);
  for I := 0 to GetArrayLength(Lines) - 1 do Done := Done + Lines[I] + #13#10;
  Progress(2, N, 'Removing other M.O.R.P.H.A. folders...');
  RunScript(Common + ' -Only Copies', Lines);
  for I := 0 to GetArrayLength(Lines) - 1 do Done := Done + Lines[I] + #13#10;
  Progress(3, N, 'Removing shortcuts...');
  RunScript(Common + ' -Only Shortcuts', Lines);
  for I := 0 to GetArrayLength(Lines) - 1 do Done := Done + Lines[I] + #13#10;
  Progress(4, N, 'Removing downloads (voice models, Python, logs)...');
  RunScript(Common + ' -Only Data', Lines);
  for I := 0 to GetArrayLength(Lines) - 1 do Done := Done + Lines[I] + #13#10;
  KillTimer(0, Keep);
  Progress(5, N, 'Done.');
end;

{ Finished: what was done. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption := 'M.O.R.P.H.A. was removed from your computer.' + #13#10#13#10 + Done + #13#10 +
      'To use M.O.R.P.H.A. again, run the M.O.R.P.H.A. setup file - it will remember you.';
end;
