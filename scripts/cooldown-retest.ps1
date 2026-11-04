# 控制变量的复测脚本：等 GPU 降温到指定温度后，重复跑 benchmark 并记录温度/功耗/频率
#
# 用法：
#   .\cooldown-retest.ps1                      # 默认 3 次，降温到 72°C
#   .\cooldown-retest.ps1 -Runs 5 -CoolTo 70   # 5 次，降温到 70°C
#
# 注意：笔记本 GPU 空载温度就在 71–73°C 附近（风扇策略保守），
# 想降到 45°C 基本要关机等半小时。更现实的做法是统一等“空载稳定温度”。
#
# 目的：验证“性能波动 39%”是否由 GPU 温度/功耗引起。

param(
    [int]$Runs = 3,
    [int]$CoolTo = 72,
    [int]$MaxWaitMin = 20,
    [string]$Model = "D:\tools\models\qwen2.5-1.5b-instruct-q4_k_m.gguf",
    [int]$Ngl = 99,
    [int]$Pp = 512,
    [int]$Tg = 128
)

$ErrorActionPreference = "Stop"

$CudaBin  = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin"
$BenchExe = "D:\tools\llama.cpp-src\build-cuda\bin\llama-bench.exe"
$Root     = Split-Path -Parent $PSScriptRoot
$RawDir   = Join-Path $Root "results\raw"
$CsvPath  = Join-Path $Root "results\cooldown-retest.csv"

$env:PATH = "$CudaBin;" + $env:PATH
New-Item -ItemType Directory -Force -Path $RawDir | Out-Null

if (-not (Test-Path $BenchExe)) { throw "找不到 llama-bench.exe: $BenchExe" }
if (-not (Test-Path $Model))    { throw "找不到模型: $Model" }

if (-not (Test-Path $CsvPath)) {
    "run,time,temp_before,max_temp,max_power_w,max_clock_mhz,pp512_ts,tg128_ts,cool_seconds" |
        Out-File -FilePath $CsvPath -Encoding UTF8
}

function Get-GpuState {
    $line = & nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu --format=csv,noheader,nounits 2>$null
    $p = $line -split ',' | ForEach-Object { $_.Trim() }
    [PSCustomObject]@{ Temp = [int]$p[0]; Power = [double]$p[1]; Clock = [int]$p[2]; Util = [int]$p[3] }
}

function Wait-Cooldown([int]$target, [int]$maxMin) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $t = (Get-GpuState).Temp
        if ($t -le $target) { return [math]::Round($sw.Elapsed.TotalSeconds, 1) }
        if ($sw.Elapsed.TotalMinutes -gt $maxMin) {
            Write-Warning "等待降温超时（当前 ${t}°C > 目标 ${target}°C），继续执行"
            return [math]::Round($sw.Elapsed.TotalSeconds, 1)
        }
        Write-Host ("  等待降温：当前 {0}°C，目标 {1}°C ..." -f $t, $target) -ForegroundColor DarkYellow
        Start-Sleep -Seconds 10
    }
}

Write-Host "==== 复测开始：$Runs 轮，降温到 ${CoolTo}°C ====" -ForegroundColor Cyan

for ($i = 1; $i -le $Runs; $i++) {
    Write-Host ""
    Write-Host "---- 第 $i / $Runs 轮 ----" -ForegroundColor Cyan

    $coolSec = Wait-Cooldown -target $CoolTo -maxMin $MaxWaitMin
    $before  = Get-GpuState
    Write-Host ("  开跑前：{0}°C, {1} W, {2} MHz" -f $before.Temp, $before.Power, $before.Clock)

    # 后台每 0.5 秒采样一次 GPU 状态
    $sampleFile = Join-Path $RawDir ("cooldown-samples-run{0}.csv" -f $i)
    $sampler = Start-Job -ScriptBlock {
        param($file, $seconds)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        "temp,power,clock,util" | Out-File -FilePath $file -Encoding UTF8
        while ($sw.Elapsed.TotalSeconds -lt $seconds) {
            $l = & nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.sm,utilization.gpu --format=csv,noheader,nounits 2>$null
            $l | Out-File -FilePath $file -Encoding UTF8 -Append
            Start-Sleep -Milliseconds 500
        }
    } -ArgumentList $sampleFile, 120

    Start-Sleep -Milliseconds 800

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $log   = Join-Path $RawDir ("$stamp-cool-run{0}.txt" -f $i)
    $benchArgs = @("-m", $Model, "-p", $Pp, "-n", $Tg, "-ngl", $Ngl, "-r", 3)
    cmd /c "`"$BenchExe`" $($benchArgs -join ' ') > `"$log`" 2>&1"

    Stop-Job $sampler -ErrorAction SilentlyContinue
    Remove-Job $sampler -Force -ErrorAction SilentlyContinue

    $text = Get-Content $log -Raw
    $ppTs = ""; $tgTs = ""
    if ($text -match "\|\s*pp$Pp\s*\|\s*([\d.]+)") { $ppTs = $Matches[1] }
    if ($text -match "\|\s*tg$Tg\s*\|\s*([\d.]+)") { $tgTs = $Matches[1] }

    $samples = @()
    if (Test-Path $sampleFile) {
        $samples = Get-Content $sampleFile | Select-Object -Skip 1 | Where-Object { $_ -match '^\d' }
    }
    $maxTemp = 0; $maxPow = 0; $maxClk = 0; $maxUtil = 0
    foreach ($s in $samples) {
        $a = $s -split ',' | ForEach-Object { $_.Trim() }
        if ($a.Count -lt 4) { continue }
        if ([int]$a[0]   -gt $maxTemp) { $maxTemp = [int]$a[0] }
        if ([double]$a[1] -gt $maxPow) { $maxPow = [double]$a[1] }
        if ([int]$a[2]   -gt $maxClk) { $maxClk = [int]$a[2] }
        if ([int]$a[3]   -gt $maxUtil) { $maxUtil = [int]$a[3] }
    }

    "{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f `
        $i, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $before.Temp, $maxTemp, $maxPow, $maxClk, $ppTs, $tgTs, $coolSec |
        Out-File -FilePath $CsvPath -Encoding UTF8 -Append

    Write-Host ("  结果：pp$Pp=$ppTs  tg$Tg=$tgTs  |  峰值 {0}°C, {1} W, {2} MHz" -f $maxTemp, $maxPow, $maxClk) -ForegroundColor Green
}

Write-Host ""
Write-Host "==== 完成，汇总数据 ====" -ForegroundColor Yellow
Get-Content $CsvPath

$rows = Import-Csv $CsvPath
if ($rows.Count -gt 1) {
    $vals = $rows | ForEach-Object { [double]$_.tg128_ts }
    $min = ($vals | Measure-Object -Minimum).Minimum
    $max = ($vals | Measure-Object -Maximum).Maximum
    $avg = ($vals | Measure-Object -Average).Average
    $spread = if ($avg -ne 0) { [math]::Round(($max - $min) / $avg * 100, 1) } else { 0 }
    Write-Host ""
    Write-Host ("tg$Tg : 最小 {0}, 最大 {1}, 平均 {2}, 极差 {3}%" -f $min, $max, [math]::Round($avg,1), $spread) -ForegroundColor Yellow
    Write-Host "（极差 < 10% 说明已控制住变量；仍 > 20% 说明还有别的因素）"
}
