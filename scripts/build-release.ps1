<#
.SYNOPSIS
  Zilisp のリリースビルドを作成する（詳細設計 §18.1）。

.DESCRIPTION
  1. 単体テスト（zig build test）を実行する。
  2. 指定したターゲットごとに ReleaseFast でビルドし、<OutputDirectory>\<target>\bin\ に出力する。

  クロスビルドが成功しても、そのターゲットの実機で動作することは保証しない（基本設計 §11）。
  配布物（ZIP・インストーラー）は作成しない。配布物は scripts/build-installer.ps1 で作成する（-Sign で署名）。

.PARAMETER OutputDirectory
  出力先。既定は リポジトリ直下の dist。

.PARAMETER Targets
  ビルドするターゲット（Zig の表記）。既定は一次ターゲットの3つ。

.PARAMETER Optimize
  最適化モード。既定は ReleaseFast（速度最優先。基本設計 §17）。

.EXAMPLE
  ./scripts/build-release.ps1
  ./scripts/build-release.ps1 -Targets x86_64-windows -OutputDirectory ./.work/build
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
    [string[]]$Targets = @('x86_64-windows', 'x86_64-linux-musl', 'aarch64-macos'),
    [ValidateSet('ReleaseFast', 'ReleaseSafe', 'ReleaseSmall', 'Debug')]
    [string]$Optimize = 'ReleaseFast'
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $repo
try {
    $zig = Get-Command zig -ErrorAction Stop
    $zigVersion = (& $zig.Source version).Trim()
    Write-Host "zig: $($zig.Source) ($zigVersion)"
    if ($zigVersion -ne '0.17.0') {
        throw "Zig 0.17.0 が必要です（検出: $zigVersion）。docs/version-update-checklist.md を参照してください。"
    }

    Write-Host '== zig build test'
    & $zig.Source build test --summary all
    if ($LASTEXITCODE -ne 0) { throw "単体テストが失敗しました（exit $LASTEXITCODE）" }

    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $out = Resolve-Path $OutputDirectory
    foreach ($t in $Targets) {
        $prefix = Join-Path $out $t
        Write-Host "== $t ($Optimize) -> $prefix"
        & $zig.Source build "-Dtarget=$t" "-Doptimize=$Optimize" --prefix $prefix
        if ($LASTEXITCODE -ne 0) { throw "$t のビルドが失敗しました（exit $LASTEXITCODE）" }
        Get-ChildItem (Join-Path $prefix 'bin') -File | ForEach-Object {
            Write-Host ("   {0}  {1:N0} bytes" -f $_.Name, $_.Length)
        }
    }
    Write-Host '完了しました。'
}
finally {
    Pop-Location
}
