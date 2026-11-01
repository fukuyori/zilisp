<#
.SYNOPSIS
  ベンチマークを実行し、結果を bench-results/ に記録する（詳細設計 §13.2）。

.DESCRIPTION
  zig build bench（ReleaseFast）の結果を bench-results/<日時>-<コミット>.tsv に保存し、
  直前の記録があれば、項目ごとの 1 回あたりの時間の比（今回 / 前回）を表示する。
  比が 1 を大きく超える項目は、性能が下がった可能性がある（基本設計 §13.4）。

.PARAMETER Filter
  名前に含まれる文字列で、実行するベンチマークを絞り込む。

.PARAMETER NoRecord
  結果を保存せず、表示だけ行う。
#>
[CmdletBinding()]
param(
    [string]$Filter,
    [switch]$NoRecord
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $repo
try {
    $benchArgs = @('build', 'bench')
    if ($Filter) { $benchArgs += @('--', $Filter) }
    $lines = & zig @benchArgs
    if ($LASTEXITCODE -ne 0) { throw "ベンチマークが失敗しました（exit $LASTEXITCODE）" }
    $lines | ForEach-Object { Write-Host $_ }

    $dir = Join-Path $repo 'bench-results'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $previous = Get-ChildItem $dir -Filter '*.tsv' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1

    if ($previous) {
        $old = @{}
        Get-Content $previous.FullName | Where-Object { $_ -notmatch '^#' -and $_ } | ForEach-Object {
            $c = $_ -split "`t"; $old[$c[0]] = [double]$c[3]
        }
        Write-Host "== 前回（$($previous.Name)）との比較（今回 / 前回）"
        $lines | Where-Object { $_ -notmatch '^#' -and $_ } | ForEach-Object {
            $c = $_ -split "`t"
            if ($old.ContainsKey($c[0]) -and $old[$c[0]] -gt 0) {
                Write-Host ("   {0,-40} {1:N3}" -f $c[0], ([double]$c[3] / $old[$c[0]]))
            } else {
                Write-Host ("   {0,-40} (前回の記録なし)" -f $c[0])
            }
        }
    }

    if (-not $NoRecord) {
        $sha = (git rev-parse --short HEAD 2>$null)
        if (-not $sha) { $sha = 'nocommit' }
        $dirty = if (git status --porcelain 2>$null) { '-dirty' } else { '' }
        $name = '{0}-{1}{2}.tsv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $sha, $dirty
        $path = Join-Path $dir $name
        $header = "# zilisp bench  date=$(Get-Date -Format o)  commit=$sha$dirty  zig=$((zig version).Trim())  host=$env:COMPUTERNAME"
        @($header) + $lines | Set-Content -Path $path -Encoding utf8
        Write-Host "記録しました: $path"
    }
}
finally {
    Pop-Location
}
