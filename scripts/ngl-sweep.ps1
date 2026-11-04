# -ngl 阶梯实验（稳健版：用 cmd 重定向到文件，再解析）
$cuda = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4\bin"
$exe  = "D:\tools\llama.cpp-src\build-cuda\bin\llama-bench.exe"
$m    = "D:\tools\models\qwen2.5-1.5b-instruct-q4_k_m.gguf"
$csv  = "D:\caozuoxitong\llamacpp-study\results\ngl-sweep.csv"
$raw  = "D:\caozuoxitong\llamacpp-study\results\raw"
$env:PATH = "$cuda;" + $env:PATH

"ngl,pp512_ts,tg128_ts" | Out-File -FilePath $csv -Encoding UTF8

foreach ($ngl in 0,5,10,15,20,24,28,99) {
    $log = Join-Path $raw ("ngl-{0}.txt" -f $ngl)
    cmd /c "`"$exe`" -m `"$m`" -p 512 -n 128 -ngl $ngl -r 2 > `"$log`" 2>&1"
    $text = Get-Content $log -Raw
    $pp = ""; $tg = ""
    if ($text -match "\|\s*pp512\s*\|\s*([\d.]+)") { $pp = $Matches[1] }
    if ($text -match "\|\s*tg128\s*\|\s*([\d.]+)") { $tg = $Matches[1] }
    "$ngl,$pp,$tg" | Out-File -FilePath $csv -Encoding UTF8 -Append
    Write-Host ("ngl={0,-3} pp512={1,-10} tg128={2}" -f $ngl, $pp, $tg)
}
Write-Host "---- done ----"
Get-Content $csv
