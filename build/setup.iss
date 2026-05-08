; Inno Setup 6 script for Critter Quitters Pest Control.
;
; Called by build.bat locally and by the windows-installer job in build.yml.
; Three parameters are required via /D on the command line:
;
;   AppVersion     — version string, e.g. "0.0.abc1234"
;   SourceExe      — full path to the Godot-exported .exe (single file, embed_pck=true)
;   OutputDir      — directory where the installer .exe will be written
;   OutputFilename — installer filename without extension

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceExe
  #error SourceExe must be defined (path to the Godot-exported game .exe)
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif
#ifndef OutputFilename
  #define OutputFilename "critter_quitters_setup"
#endif

#define AppName      "Critter Quitters Pest Control"
#define AppPublisher "Tim Goergen"
#define AppURL       "https://github.com/TimGoergen/critter-quitters"
#define AppExeName   "critter_quitters.exe"

[Setup]
; AppId is a stable GUID that Windows uses for uninstall/update tracking.
; Do not change this after the game ships.
AppId={{F4A2B8E1-3C7D-4F9A-B5E2-1D8C6F3A7E9B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
; PrivilegesRequired=lowest installs to the user's local Programs folder without needing admin
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The game is a single self-contained .exe (Godot export_presets.cfg: binary_format/embed_pck=true)
Source: "{#SourceExe}"; DestDir: "{app}"; DestName: "{#AppExeName}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";                          Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}";    Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}";                  Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
