param(
    [string]$SourceRoot,
    [string]$TargetRoot
)

if (-not $SourceRoot) { $SourceRoot = Read-Host "Enter source folder" }
if (-not $TargetRoot) { $TargetRoot = Read-Host "Enter destination folder" }

$Speed = 1.03

if (!(Test-Path $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot | Out-Null
}

Get-ChildItem -Path $SourceRoot -Recurse -Filter *.flac | ForEach-Object {

    $relative = $_.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $outFile  = Join-Path $TargetRoot $relative
    $outDir   = Split-Path $outFile -Parent

    if (!(Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $sr = & ffprobe -v error -select_streams a:0 `
        -show_entries stream=sample_rate `
        -of default=noprint_wrappers=1:nokey=1 `
        "$($_.FullName)"

    if (-not $sr) {
        Write-Host "Skipping (no sample rate):" $_.FullName
        return
    }

    $newRate = [int]([double]$sr * $Speed)

    Write-Host "Processing:" $_.Name

    ffmpeg -y -loglevel error -i "$($_.FullName)" `
        -filter:a "asetrate=$newRate,aresample=$sr" `
        "$outFile"
}

Write-Host "DONE"
