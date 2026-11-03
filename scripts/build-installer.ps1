<#
.SYNOPSIS
  Zilisp の配布物（Windows 用インストーラーと、ターゲットごとの ZIP）を作成する（詳細設計 §18）。

.DESCRIPTION
  1. scripts/build-release.ps1 でリリースビルドを作成する（-SkipBuild なら、既にある dist を使う）。
  2. -Sign なら、zilisp.exe（x86_64-windows）に電子署名を付ける（インストーラーに入れる前）。
  3. Inno Setup（ISCC.exe）で installer/zilisp.iss からインストーラーを作成する。
     -Sign なら、アンインストーラーとインストーラー本体にも署名する（Inno Setup の SignTool・SignedUninstaller）。
  4. ターゲットごとに ZIP を作成する（実行ファイル、LICENSE、Unicode のライセンス（LICENSE-UNICODE.txt）、README・CHANGELOG の英語版と日本語版）。
  5. -Sign なら、zilisp.exe とインストーラーの署名を確かめる。

  署名に使う証明書は、環境変数 CODESIGN_CERT（証明書のサブジェクト名。現在の利用者の証明書ストアから
  signtool の /n で選ぶ）で指定する。-Sign を指定して CODESIGN_CERT が未設定なら、エラーで停止する。
  署名付きの配布物は利用者が -Sign を付けて作成する（Claude は配布物を作成しない）。
  GitHub Actions のリリース（.github/workflows/release.yml）は、-Sign なしで実行して署名のない配布物を登録する。

.PARAMETER Sign
  実行ファイル・アンインストーラー・インストーラーに電子署名を付ける。

.PARAMETER SkipBuild
  リリースビルドを作り直さず、OutputDirectory にあるものを使う。

.PARAMETER OutputDirectory
  リリースビルドの出力先（build-release.ps1 と同じ）。配布物は <OutputDirectory>\release\ に出力する。

.PARAMETER Targets
  ZIP を作るターゲット（build-release.ps1 に渡す）。インストーラーは x86_64-windows だけ。

.PARAMETER TimestampUrl
  署名のタイムスタンプのサーバー（RFC 3161）。

.EXAMPLE
  ./scripts/build-installer.ps1 -Sign
  ./scripts/build-installer.ps1 -Sign -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$Sign,
    [switch]$SkipBuild,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
    [string[]]$Targets = @('x86_64-windows', 'x86_64-linux-musl', 'aarch64-macos'),
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    # バージョン（build.zig.zon と src/version.zig が一致していること）
    $zon = Get-Content -Raw (Join-Path $repo 'build.zig.zon')
    if ($zon -notmatch '\.version\s*=\s*"([^"]+)"') { throw 'build.zig.zon に .version がありません' }
    $version = $Matches[1]
    $vzig = Get-Content -Raw (Join-Path $repo 'src\version.zig')
    if ($vzig -notmatch 'pub const version = "([^"]+)"') { throw 'src/version.zig に version がありません' }
    if ($Matches[1] -ne $version) {
        throw "build.zig.zon（$version）と src/version.zig（$($Matches[1])）のバージョンが違います。docs/version-update-checklist.md を参照してください。"
    }
    Write-Host "version: $version"

    # 署名の準備
    $signtool = $null
    if ($Sign) {
        if (-not $env:CODESIGN_CERT) { throw '-Sign を指定しましたが、環境変数 CODESIGN_CERT が設定されていません。' }
        $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $signtool = $cmd.Source
        } else {
            $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
            $signtool = Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $signtool) { throw 'signtool.exe が見つかりません（Windows SDK をインストールしてください）。' }
        Write-Host "signtool: $signtool"
    } else {
        Write-Warning '-Sign を指定していないので、署名のない配布物を作成します（確認用。配布しないこと）。'
    }

    $iscc = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup 6（ISCC.exe）が見つかりません。' }
    Write-Host "ISCC: $iscc"

    # 1. リリースビルド
    if (-not $SkipBuild) {
        & (Join-Path $PSScriptRoot 'build-release.ps1') -OutputDirectory $OutputDirectory -Targets $Targets
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "リリースビルドが失敗しました（exit $LASTEXITCODE）" }
    }
    $out = (Resolve-Path $OutputDirectory).Path
    $winBin = Join-Path $out 'x86_64-windows\bin'
    $exe = Join-Path $winBin 'zilisp.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "$exe がありません（x86_64-windows のリリースビルドが必要です）。" }
    $release = Join-Path $out 'release'
    New-Item -ItemType Directory -Force $release | Out-Null

    # 署名（タイムスタンプ付き）
    function Invoke-Sign([string]$path) {
        & $signtool sign /n $env:CODESIGN_CERT /fd sha256 /tr $TimestampUrl /td sha256 $path
        if ($LASTEXITCODE -ne 0) { throw "署名が失敗しました: $path（exit $LASTEXITCODE）" }
    }
    function Test-Signature([string]$path) {
        & $signtool verify /pa $path
        if ($LASTEXITCODE -ne 0) { throw "署名の確認が失敗しました: $path（exit $LASTEXITCODE）" }
    }

    # 2. 実行ファイルの署名（インストーラー・ZIP に入れる前）
    if ($Sign) {
        Write-Host '== 署名: zilisp.exe'
        Invoke-Sign $exe
    }

    # 3. インストーラー
    Write-Host '== インストーラー'
    $isccArgs = @(
        "/DAppVersion=$version",
        "/DSourceDir=$winBin",
        "/DRepoDir=$repo",
        "/DOutputDir=$release"
    )
    if ($Sign) {
        # Inno Setup が $f をファイル名に、$q を " に置き換えて、アンインストーラーとインストーラー本体に署名する
        $isccArgs += '/DSign'
        $isccArgs += ('/Szlsign=$q' + $signtool + '$q sign /n $q' + $env:CODESIGN_CERT + '$q /fd sha256 /tr ' + $TimestampUrl + ' /td sha256 $f')
    }
    $isccArgs += (Join-Path $repo 'installer\zilisp.iss')
    & $iscc @isccArgs
    if ($LASTEXITCODE -ne 0) { throw "インストーラーの作成が失敗しました（exit $LASTEXITCODE）" }
    $setup = Join-Path $release "zilisp-$version-x86_64-windows-setup.exe"
    if (-not (Test-Path -LiteralPath $setup)) { throw "$setup がありません。" }

    # 4. ZIP（ターゲットごと）
    foreach ($t in $Targets) {
        $bin = Join-Path $out "$t\bin"
        if (-not (Test-Path -LiteralPath $bin)) { Write-Warning "$t のビルドがないので ZIP を作りません: $bin"; continue }
        $stage = Join-Path $release "zilisp-$version-$t"
        if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force $stage }
        New-Item -ItemType Directory -Force (Join-Path $stage 'bin') | Out-Null
        Copy-Item (Join-Path $bin '*') (Join-Path $stage 'bin')
        Copy-Item ('LICENSE', 'README.md', 'README.ja.md', 'CHANGELOG.md', 'CHANGELOG.ja.md' | ForEach-Object { Join-Path $repo $_ }) $stage
        # 文字の表は Unicode の UCD から作るので、Unicode License v3 の表示を付ける
        Copy-Item (Join-Path $repo 'data\unicode\LICENSE.txt') (Join-Path $stage 'LICENSE-UNICODE.txt')
        $zip = "$stage.zip"
        if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
        Compress-Archive -Path $stage -DestinationPath $zip
        Remove-Item -Recurse -Force $stage
        Write-Host "   $zip"
    }

    # 5. 署名の確認
    if ($Sign) {
        Write-Host '== 署名の確認'
        Test-Signature $exe
        Test-Signature $setup
    }

    Get-ChildItem $release -File | ForEach-Object { Write-Host ("   {0}  {1:N0} bytes" -f $_.Name, $_.Length) }
    if (-not $Sign) { Write-Warning '署名のない配布物です。配布には -Sign を付けて作り直してください。' }
    Write-Host '完了しました。'
}
finally {
    Pop-Location
}
