param(
    [string]$SourceRoot,
    [string]$TargetRoot,
    [double]$Speed = 1.04
)

$ErrorActionPreference = "Stop"

if (-not $SourceRoot) {
    $SourceRoot = Read-Host "Enter source folder"
}

if (-not $TargetRoot) {
    $TargetRoot = Read-Host "Enter destination folder"
}

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

Write-Host ""
Write-Host "Source      : $SourceRoot"
Write-Host "Destination : $TargetRoot"
Write-Host "Pitch/Speed : ${Speed}x"
Write-Host ""

$Success = 0
$Failed  = 0

$Files = @(
    Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter "*.flac"
)

Write-Host "FLAC files found: $($Files.Count)"
Write-Host ""

foreach ($File in $Files) {
    $tempFile = $null

    try {
        $relative = $File.FullName.Substring($SourceRoot.Length).TrimStart('\')
        $outFile = Join-Path $TargetRoot $relative
        $outDir  = Split-Path -Parent $outFile

        if (-not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($outFile)
        $tempFile = Join-Path $outDir ("." + $baseName + ".processing.flac")

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

        if ($sr -le 0) {
            throw "Invalid sample rate reported by ffprobe: $sr"
        }

        $newRate = [int64][Math]::Round(
            [double]$sr * $Speed,
            0,
            [MidpointRounding]::AwayFromZero
        )

        Write-Host "------------------------------------------------------------"
        Write-Host "Processing : $($File.Name)"
        Write-Host "Sample rate: $sr Hz -> $newRate Hz -> $sr Hz"

        $audioFilter = `
            "asetrate=$newRate," +
            "aresample=${sr}:resampler=soxr:precision=33:cheby=1"

        & ffmpeg `
            -hide_banner `
            -y `
            -v warning `
            -i $File.FullName `
            -map "0:a:0" `
            -map "0:v?" `
            -map_metadata 0 `
            -map_chapters 0 `
            -af $audioFilter `
            -c:a flac `
            -c:v copy `
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

        $verifyCodec = & ffprobe `
            -v error `
            -select_streams "a:0" `
            -show_entries "stream=codec_name" `
            -of "default=noprint_wrappers=1:nokey=1" `
            $tempFile

        if ($LASTEXITCODE -ne 0 -or -not $verifyCodec) {
            throw "Output audio verification failed."
        }

        if ($verifyCodec.Trim() -ne "flac") {
            throw "Output codec verification failed: $verifyCodec"
        }

        $verifyRate = & ffprobe `
            -v error `
            -select_streams "a:0" `
            -show_entries "stream=sample_rate" `
            -of "default=noprint_wrappers=1:nokey=1" `
            $tempFile

        if ($LASTEXITCODE -ne 0 -or -not $verifyRate) {
            throw "Unable to verify output sample rate."
        }

        if ([int64]$verifyRate.Trim() -ne $sr) {
            throw "Output sample rate does not match source sample rate."
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
Write-Host "DONE"
Write-Host "============================================================"
Write-Host "Total      : $($Files.Count)"
Write-Host "Successful : $Success"
Write-Host "Failed     : $Failed"
Write-Host "============================================================"
