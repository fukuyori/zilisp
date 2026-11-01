<#
.SYNOPSIS
  教材（CommonLispBasicMaster）のコードブロックを抽出し、分類の候補を作る（詳細設計 §12）。

.DESCRIPTION
  1. 教材を .work/CommonLispBasicMaster に取得し、固定したコミットに合わせる。
  2. zig build extract-samples で Markdown から Lisp のブロックを抽出する（.work/samples）。
  3. SBCL で、評価せずに読み込むだけで分類の候補を作る（tools/classify_samples/classify.lisp）。
  4. 集計を compatibility/curriculum-inventory.md に書く。
     compatibility/manifest.toml は、まだ存在しない場合だけ作る（手作業の分類を上書きしないため）。

  教材のコードそのものはリポジトリに入れない（.work/ は git の管理対象外）。

.PARAMETER Commit
  対象とする教材のコミット。既定は固定したコミット。

.PARAMETER UpdateManifest
  compatibility/manifest.toml が存在しても作り直す（手作業の分類は失われる）。
#>
[CmdletBinding()]
param(
    [string]$Commit = '639544c8133fdc51ffe4c2184aad785345128419',
    [switch]$UpdateManifest
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $repo
try {
    $src = Join-Path $repo '.work/CommonLispBasicMaster'
    $out = Join-Path $repo '.work/samples'
    if (-not (Test-Path $src)) {
        git clone --quiet https://github.com/fukuyori/CommonLispBasicMaster.git $src
        if ($LASTEXITCODE -ne 0) { throw '教材の取得に失敗しました' }
    }
    $head = (git -C $src rev-parse HEAD).Trim()
    if ($head -ne $Commit) {
        git -C $src fetch --quiet origin
        git -C $src -c advice.detachedHead=false checkout --quiet $Commit
        if ($LASTEXITCODE -ne 0) { throw "コミット $Commit に合わせられませんでした" }
    }
    Write-Host "教材: $src @ $Commit"

    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    & zig build extract-samples -- $src $out
    if ($LASTEXITCODE -ne 0) { throw "抽出に失敗しました（exit $LASTEXITCODE）" }

    & sbcl --script (Join-Path $repo 'tools/classify_samples/classify.lisp') $out $Commit
    if ($LASTEXITCODE -ne 0) { throw "分類に失敗しました（exit $LASTEXITCODE）" }

    $compat = Join-Path $repo 'compatibility'
    New-Item -ItemType Directory -Force $compat | Out-Null
    Copy-Item (Join-Path $out 'inventory.md') (Join-Path $compat 'curriculum-inventory.md') -Force
    Write-Host "更新しました: compatibility/curriculum-inventory.md"

    $manifest = Join-Path $compat 'manifest.toml'
    if ($UpdateManifest -or -not (Test-Path $manifest)) {
        Copy-Item (Join-Path $out 'manifest.toml') $manifest -Force
        Write-Host "作成しました: compatibility/manifest.toml"
    } else {
        Write-Host "compatibility/manifest.toml は既にあるため上書きしません（新しい版: .work/samples/manifest.toml）"
    }
}
finally {
    Pop-Location
}
