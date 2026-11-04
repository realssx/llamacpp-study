# 跑完整的量化 × 后端矩阵，结果追加到 results/benchmark.csv
$env:PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin;" + $env:PATH
$bin    = "D:\tools\llama.cpp-src\build-cuda\bin"
$models = "D:\tools\models"
$csv    = "D:\caozuoxitong\llamacpp-study\results\benchmark.csv"
$raw    = "D:\caozuoxitong\llamacpp-study\results\raw"
New-Item -ItemType Directory -Force -Path $raw | Out-Null

if (-not (Test-Path $csv)) {
    "date,model,backend,ngl,pp,tg,pp_ts,tg_ts,notes" | Out-File -FilePath $csv -Encoding UTF8
}

$quants = @("q4_k_m", "q5_k_m", "q8_0")

foreach ($q in $quants) {
    $m = Join-Path $models "qwen2.5-1.5b-instruct-$q.gguf"
    foreach ($cfg in @(@{b="CUDA"; ngl=99; t=0}, @{b="CPU"; ngl=0; t=16})) {
        $tag = "$q-$($cfg.b)"
        Write-Host "==== $tag ====" -ForegroundColor Cyan
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $benchArgs = @("-m", $m, "-p", 512, "-n", 128, "-ngl", $cfg.ngl, "-r", 3)
        if ($cfg.t -gt 0) { $benchArgs += @("-t", $cfg.t) }
        $out = & (Join-Path $bin "llama-bench.exe") @benchArgs 2>&1
        $out | Out-File -FilePath (Join-Path $raw "$stamp-$tag.txt") -Encoding UTF8

        $pp = ""; $tg = ""
        foreach ($line in $out) {
            if ($line -match "\|\s*pp512\s*\|\s*([\d.]+)") { $pp = $Matches[1] }
            if ($line -match "\|\s*tg128\s*\|\s*([\d.]+)") { $tg = $Matches[1] }
        }
        $note = if ($cfg.b -eq "CPU") { "16 threads" } else { "RTX 4060 8GB" }
        "{0},{1},{2},{3},512,128,{4},{5},{6}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), "qwen2.5-1.5b-$q", $cfg.b, $cfg.ngl, $pp, $tg, $note |
            Out-File -FilePath $csv -Encoding UTF8 -Append
        Write-Host "  pp512=$pp  tg128=$tg" -ForegroundColor Green
    }
}
Write-Host "全部完成" -ForegroundColor Yellow
Get-Content $csv
