[Setup]
AppName=Flumi
AppVersion=1.0.3
AppPublisher=Outpoot
AppPublisherURL=https://github.com/gurted/flumi
AppSupportURL=https://github.com/gurted/flumi/issues
AppUpdatesURL=https://github.com/gurted/flumi/releases
DefaultDirName={autopf}\Flumi
DefaultGroupName=Flumi
AllowNoIcons=yes
LicenseFile=
InfoBeforeFile=
InfoAfterFile=
OutputDir=Windows\installer
OutputBaseFilename=Flumi-Setup-{#SetupSetting("AppVersion")}
SetupIconFile=..\Assets\gurted.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Files]
Source: "Windows\Flumi.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "Windows\Flumi.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "Windows\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\Flumi"; Filename: "{app}\Flumi.exe"
Name: "{group}\{cm:UninstallProgram,Flumi}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Flumi"; Filename: "{app}\Flumi.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Flumi"; Filename: "{app}\Flumi.exe"; Tasks: quicklaunchicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\gurt"; ValueType: string; ValueName: ""; ValueData: "GURT Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\gurt"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\gurt\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\Flumi.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\gurt\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Flumi.exe"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\Flumi.exe"; Description: "{cm:LaunchProgram,Flumi}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Flumi"

[Code]
procedure InitializeWizard;
begin
  WizardForm.LicenseAcceptedRadio.Checked := True;
end;