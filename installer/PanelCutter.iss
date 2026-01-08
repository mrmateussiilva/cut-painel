; Inno Setup script - PanelCutter
; Build:
;   iscc.exe PanelCutter.iss /DMyAppVersion=0.1.0 /DSourceDir="C:\path\to\release\windows\PanelCutter"

#define MyAppName "PanelCutter"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\\release\\windows\\PanelCutter"
#endif

[Setup]
AppId={{3D3B2D87-8E1C-4D1E-9B91-6F8C6B7D4C12}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=PanelCutter
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\release\windows
OutputBaseFilename=PanelCutter-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\PanelCutter.exe"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\PanelCutter.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Run]
Filename: "{app}\PanelCutter.exe"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
