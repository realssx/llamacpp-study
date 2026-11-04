# 一键跑 llama-bench 并记录结果
#
# 用法示例：
#   .\bench.ps1 -Model "D:\tools\models\qwen2.5-1.5b-instruct-q4_k_m.gguf" -Backend cuda -Ngl 99
#   .\bench.ps1 -Model "...q4_k_m.gguf" -Backend cpu -Ngl 0 -Notes "纯CPU 16线程"

param(
    [Parameter(Mandatory = $true)][string]$Model,
    [ValidateSet("cuda", "cpu")][string]$Backend = "cuda",
    [int]$Ngl = 99,
    [int]$Pp = 512,
    [int]$Tg = 128,
    [int]$Threads = 0,
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"

# ---- 配置：改成你的实际路径 ----
$BenchExe = "D:\tools\llamacpp\llama-bench.exe"
$Root     = Split-Path -Parent $PSScriptRoot
$RawDir   = Join-Path $Root "results\raw"
$CsvPath  = Join-Path $Root "results\benchmark.csv"

if (-not (Test-Path $BenchExe)) { throw "找不到 llama-bench.exe：$BenchExe（请先修改脚本里的路径）" }
if (-not (Test-Path $Model))    { throw "找不到模型文件：$Model" }

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$rawFile = Join-Path $RawDir "$stamp-$Backend-ngl$Ngl.txt"

$args = @("-m", $Model, "-p", $Pp, "-n", $Tg, "-ngl", $Ngl, "-r", 3)
if ($Threads -gt 0) { $args += @("-t", $Threads) }

Write-Host "运行：$BenchExe $($args -join ' ')" -ForegroundColor Cyan
$output = & $BenchExe @args 2>&1
$output | Tee-Object -FilePath $rawFile

# ---- 解析 pp / tg 的 tokens per second ----
$ppTs = ""
$tgTs = ""
foreach ($line in $output) {
    if ($line -match "\|\s*pp$Pp\s*\|\s*([\d.]+)") { $ppTs = $Matches[1] }
    if ($line -match "\|\s*tg$Tg\s*\|\s*([\d.]+)") { $tgTs = $Matches[1] }
}

$row = [PSCustomObject]@{
    date    = (Get-Date -Format "yyyy-MM-dd HH:mm")
    model   = (Split-Path $Model -Leaf)
    backend = $Backend
    ngl     = $Ngl
    pp      = $Pp
    tg      = $Tg
    pp_ts   = $ppTs
    tg_ts   = $tgTs
    notes   = $Notes
}

if (-not (Test-Path $CsvPath)) {
    $row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
} else {
    $row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -Append
}

Write-Host ""
Write-Host "已记录：pp ≈ $ppTs t/s, tg ≈ $tgTs t/s" -ForegroundColor Green
Write-Host "原始输出：$rawFile"
Write-Host "汇总表格：$CsvPath"
