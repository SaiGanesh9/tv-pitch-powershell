param(
    [string]$SourceRoot,
    [string]$TargetRoot,
    [double]$Speed = 1.04
)

$ErrorActionPreference = "Stop"

if (-not $SourceRoot) { $SourceRoot = Read-Host "Enter source folder" }
if (-not $TargetRoot) { $TargetRoot = Read-Host "Enter destination folder" }

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg.exe was not found in PATH."
}
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffprobe.exe was not found in PATH."
}
if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Source folder does not exist: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path.TrimEnd('\')
$TargetRoot = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')

function Get-Mp3SampleRate([int64]$SourceRate) {
    # Keep native standard MP3 rates where possible.
    if ($SourceRate -eq 32000 -or $SourceRate -eq 44100 -or $SourceRate -eq 48000) {
        return $SourceRate
    }

    # Preserve the common 44.1 kHz and 48 kHz sample-rate families.
    if ($SourceRate -in @(22050, 44100, 88200, 176400, 352800)) {
        return 44100
    }

    if ($SourceRate -in @(24000, 48000, 96000, 192000, 384000)) {
        return 48000
    }

    # Sensible fallback for unusual music files.
    if ($SourceRate -lt 46050) {
        return 44100
    }

    return 48000
}

Write-Host ""
Write-Host "Source      : $SourceRoot"
Write-Host "Destination : $TargetRoot"
Write-Host "Pitch/Speed : ${Speed}x"
Write-Host "MP3 bitrate : 320 kbps CBR"
Write-Host ""

$Success = 0
$Failed = 0

$Files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter "*.flac")
Write-Host "FLAC files found: $($Files.Count)"
Write-Host ""

foreach ($File in $Files) {
    $tempFile = $null

    try {
        $relative = $File.FullName.Substring($SourceRoot.Length).TrimStart('\')
        $relativeMp3 = [System.IO.Path]::ChangeExtension($relative, ".mp3")
        $outFile = Join-Path $TargetRoot $relativeMp3
        $outDir = Split-Path -Parent $outFile

        if (-not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($outFile)
        $tempFile = Join-Path $outDir ("." + $baseName + ".processing.mp3")

        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force
        }

        $srOutput = & ffprobe `
            -v error `
            -select_streams "a:0" `
            -show_entries "stream=sample_rate" `
            -of "default=noprint_wrappers=1:nokey=1" `
            $File.FullName

        if ($LASTEXITCODE -ne 0 -or -not $srOutput) {
            throw "Unable to determine source sample rate."
        }

        $sr = [int64]$srOutput.Trim()
        if ($sr -le 0) { throw "Invalid source sample rate: $sr" }

        $newRate = [int64][Math]::Round(
            [double]$sr * $Speed,
            0,
            [MidpointRounding]::AwayFromZero
        )

        $mp3Rate = Get-Mp3SampleRate $sr

        Write-Host "------------------------------------------------------------"
        Write-Host "Processing : $($File.Name)"
        Write-Host "Pitch rate : $sr Hz -> $newRate Hz"
        Write-Host "MP3 output : $mp3Rate Hz / 320 kbps"

        # asetrate changes pitch + speed together.
        # SoXR then resamples once to the final MP3-compatible sample rate.
        $audioFilter = `
            "asetrate=$newRate," +
            "aresample=${mp3Rate}:resampler=soxr:precision=33:cheby=1"

        & ffmpeg `
            -hide_banner `
            -y `
            -v warning `
            -i $File.FullName `
            -map "0:a:0" `
            -map "0:v:0?" `
            -map_metadata 0 `
            -map_chapters 0 `
            -af $audioFilter `
            -c:a libmp3lame `
            -b:a 320k `
            -c:v copy `
            -id3v2_version 3 `
            $tempFile

        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg failed with exit code $LASTEXITCODE."
        }

        if (-not (Test-Path -LiteralPath $tempFile)) {
            throw "FFmpeg finished without creating an output file."
        }
        if ((Get-Item -LiteralPath $tempFile).Length -le 0) {
            throw "Output file is empty."
        }

        $verify = & ffprobe `
            -v error `
            -select_streams "a:0" `
            -show_entries "stream=codec_name,sample_rate,bit_rate" `
            -of "default=noprint_wrappers=1:nokey=0" `
            $tempFile

        if ($LASTEXITCODE -ne 0 -or -not $verify) {
            throw "Output verification failed."
        }

        $verifyText = ($verify -join "`n")
        if ($verifyText -notmatch "codec_name=mp3") {
            throw "Output codec is not MP3."
        }
        if ($verifyText -notmatch "sample_rate=$mp3Rate") {
            throw "Output sample rate verification failed."
        }

        if (Test-Path -LiteralPath $outFile) {
            Remove-Item -LiteralPath $outFile -Force
        }

        Move-Item -LiteralPath $tempFile -Destination $outFile -Force
        $tempFile = $null

        Write-Host "SUCCESS    : $outFile"
        Write-Host ""
        $Success++
    }
    catch {
        $Failed++
        Write-Warning "FAILED: $($File.FullName)"
        Write-Warning $_.Exception.Message

        if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        Write-Host ""
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "DONE - FLAC -> MP3 320 kbps"
Write-Host "============================================================"
Write-Host "Total      : $($Files.Count)"
Write-Host "Successful : $Success"
Write-Host "Failed     : $Failed"
Write-Host "============================================================"
