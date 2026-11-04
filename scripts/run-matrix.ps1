# 跑完整的量化 × 后端矩阵（热稳态版）
#
# 每轮开跑前等待 GPU 回到空载稳定温度，避免“冷机首跑偏快”污染对比结果。
#
# 用法：.\run-matrix.ps1                 # 默认等温到 72°C
#       .\run-matrix.ps1 -CoolTo 70      # 换个等温目标

param(
    [int]$CoolTo = 75,
    [int]$MaxWaitMin = 5,
    [int]$Rep = 3
)

$CudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin"
$Bin     = "D:\tools\llama.cpp-src\build-cuda\bin"
$Models  = "D:\tools\models"
$Root    = Split-Path -Parent $PSScriptRoot
$Csv     = Join-Path $Root "results\benchmark.csv"
$RawDir  = Join-Path $Root "results\raw"

$env:PATH = "$CudaBin;" + $env:PATH
New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

if (-not (Test-Path $Csv)) {
    "date,model,backend,ngl,pp,tg,pp_ts,tg_ts,notes" | Out-File -FilePath $Csv -Encoding UTF8
}

function Get-GpuTemp {
    $v = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
    return [int]$v
}

function Wait-GpuCool([int]$target, [int]$maxMin) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $t = Get-GpuTemp
        if ($t -le $target) { return $t }
        if ($sw.Elapsed.TotalMinutes -gt $maxMin) {
            Write-Warning "降温超时（${t}°C > ${target}°C），继续"
            return $t
        }
        Write-Host ("  等待降温：{0}°C -> 目标 {1}°C" -f $t, $target) -ForegroundColor DarkYellow
        Start-Sleep -Seconds 10
    }
}

$quants = @("q4_k_m", "q5_k_m", "q8_0")

foreach ($q in $quants) {
    $m = Join-Path $Models "qwen2.5-1.5b-instruct-$q.gguf"
    foreach ($cfg in @(@{b="CUDA"; ngl=99; t=0}, @{b="CPU"; ngl=0; t=16})) {
        $tag = "$q-$($cfg.b)"
        Write-Host ""
        Write-Host "==== $tag ====" -ForegroundColor Cyan

        $startTemp = Wait-GpuCool -target $CoolTo -maxMin $MaxWaitMin
        Write-Host ("  开跑温度：{0}°C" -f $startTemp) -ForegroundColor DarkGray

        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $log   = Join-Path $RawDir "$stamp-$tag.txt"
        $benchArgs = @("-m", $m, "-p", 512, "-n", 128, "-ngl", $cfg.ngl, "-r", $Rep)
        if ($cfg.t -gt 0) { $benchArgs += @("-t", $cfg.t) }
        cmd /c "`"$(Join-Path $Bin 'llama-bench.exe')`" $($benchArgs -join ' ') > `"$log`" 2>&1"

        $text = Get-Content $log -Raw
        $ppTs = ""; $tgTs = ""
        if ($text -match "\|\s*pp512\s*\|\s*([\d.]+)") { $ppTs = $Matches[1] }
        if ($text -match "\|\s*tg128\s*\|\s*([\d.]+)") { $tgTs = $Matches[1] }

        $note = if ($cfg.b -eq "CPU") { "16 threads start=${startTemp}C" } else { "RTX 4060 8GB start=${startTemp}C" }
        "{0},{1},{2},{3},512,128,{4},{5},{6}" -f `
            (Get-Date -Format "yyyy-MM-dd HH:mm"), "qwen2.5-1.5b-$q", $cfg.b, $cfg.ngl, $ppTs, $tgTs, $note |
            Out-File -FilePath $Csv -Encoding UTF8 -Append

        Write-Host ("  pp512=$ppTs  tg128=$tgTs") -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==== 完成 ====" -ForegroundColor Yellow
Get-Content $Csv
