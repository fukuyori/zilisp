; Zilisp の Windows 用インストーラー（Inno Setup 6。詳細設計 §18）
; scripts/build-installer.ps1 から ISCC.exe で作成する。直接 ISCC を実行する場合は、次の定義を渡すこと。
;   /DAppVersion=0.2.0          バージョン（build.zig.zon の .version。スクリプトが読んで渡す）
;   /DSourceDir=<dir>           zilisp.exe のあるディレクトリ（dist\x86_64-windows\bin）
;   /DRepoDir=<dir>             リポジトリのディレクトリ（LICENSE・README・CHANGELOG を入れる）
;   /DOutputDir=<dir>           インストーラーの出力先
;   /DSign                      署名する（ISCC に /Szlsign=... を渡すこと。アンインストーラーにも署名する）

#ifndef AppVersion
  #error AppVersion を定義してください（scripts/build-installer.ps1 から実行する）
#endif
#ifndef SourceDir
  #error SourceDir を定義してください
#endif
#ifndef RepoDir
  #error RepoDir を定義してください
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{8C3A4E2B-6B1F-4C55-9E2D-1F7A0B3C5D21}
AppName=Zilisp
AppVersion={#AppVersion}
AppVerName=Zilisp {#AppVersion}
AppPublisher=fukuyori
AppPublisherURL=https://github.com/fukuyori/zilisp
AppSupportURL=https://github.com/fukuyori/zilisp
DefaultDirName={autopf}\Zilisp
DefaultGroupName=Zilisp
DisableProgramGroupPage=yes
LicenseFile={#RepoDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=zilisp-{#AppVersion}-x86_64-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 管理者権限なしでも、利用者ごとにインストールできる
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ChangesEnvironment=yes
UninstallDisplayName=Zilisp {#AppVersion}
#ifdef Sign
SignTool=zlsign
SignedUninstaller=yes
#endif

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "PATH に Zilisp の bin ディレクトリを加える"; Flags: unchecked

[Files]
Source: "{#SourceDir}\zilisp.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#RepoDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
; 文字の表は Unicode の UCD から作るので、Unicode License v3 の表示を付ける
Source: "{#RepoDir}\data\unicode\LICENSE.txt"; DestDir: "{app}"; DestName: "LICENSE-UNICODE.txt"; Flags: ignoreversion
Source: "{#RepoDir}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoDir}\README.ja.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoDir}\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoDir}\CHANGELOG.ja.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Zilisp REPL"; Filename: "{app}\bin\zilisp.exe"
Name: "{group}\{cm:UninstallProgram,Zilisp}"; Filename: "{uninstallexe}"

[Code]
const
  EnvKeyUser = 'Environment';
  EnvKeyMachine = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function EnvRoot: Integer;
begin
  if IsAdminInstallMode then Result := HKEY_LOCAL_MACHINE else Result := HKEY_CURRENT_USER;
end;

function EnvKey: String;
begin
  if IsAdminInstallMode then Result := EnvKeyMachine else Result := EnvKeyUser;
end;

function BinDir: String;
begin
  Result := ExpandConstant('{app}\bin');
end;

{ PATH の要素に dir があるか（大文字・小文字を区別しない） }
function PathHas(const Path, Dir: String): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';') > 0;
end;

procedure AddToPath;
var
  Path: String;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then Path := '';
  if PathHas(Path, BinDir) then exit;
  if (Path <> '') and (Copy(Path, Length(Path), 1) <> ';') then Path := Path + ';';
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path + BinDir);
end;

procedure RemoveFromPath;
var
  Path, Dir: String;
  P: Integer;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then exit;
  Dir := BinDir;
  Path := ';' + Path + ';';
  P := Pos(';' + Uppercase(Dir) + ';', Uppercase(Path));
  if P = 0 then exit;
  Delete(Path, P, Length(Dir) + 1);
  { 前後に加えた ; を外す }
  if Copy(Path, 1, 1) = ';' then Delete(Path, 1, 1);
  if Copy(Path, Length(Path), 1) = ';' then Delete(Path, Length(Path), 1);
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then AddToPath;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then RemoveFromPath;
end;
