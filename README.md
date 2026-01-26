# TV Pitch Audio Converter (PowerShell)

PowerShell scripts that apply TV-style speed and pitch increase to audio files using FFmpeg,
while preserving the original folder structure.

---

## Features

- Applies speed and pitch together (default: +3%)
- Preserves full directory structure
- Supports **FLAC** and **MP3** workflows
- Uses **ffprobe** to read actual sample rate (compatible with older FFmpeg builds)
- No hardcoded paths; source and destination are passed as arguments

---

## Requirements

- Windows 10 or Windows 11
- **FFmpeg** with **ffprobe** available in system **PATH**

Download FFmpeg from:

```https://www.gyan.dev/ffmpeg/builds/```

After extraction, add: ```C:\ffmpeg\bin``` to the system ```PATH```.

Verify in cmd: ```ffmpeg -version ffprobe -version```

---

## PowerShell Execution Policy (First Time Only)

Run this PowerShell in Administrator: ```Set-ExecutionPolicy RemoteSigned -Scope CurrentUser```

---

## Usage

Run scripts with ```source``` and ```destination``` folders as arguments:

### FLAC → FLAC
```.\scripts\flac_to_flac_tv_pitch.ps1 "D:\Songs_Original" "E:\Songs_TV_Pitch"```

### FLAC → MP3
```.\scripts\flac_to_mp3_tv_pitch.ps1 "D:\Songs_Original" "E:\Songs_TV_Pitch_MP3"```

### MP3 → MP3
```.\scripts\mp3_to_mp3_tv_pitch.ps1 "D:\Songs_MP3" "E:\Songs_TV_Pitch_MP3"```

If arguments are not provided, the script will prompt for folders interactively.

---

## Folder Structure Example

Source:
```
D:\Songs_Original 
    └─ Movie1 
        └─ song1.flac 
    └─ Movie2 
        └─ song2.flac
```
Target:
```
E:\Songs_TV_Pitch
```
Output:
```
E:\Songs_TV_Pitch 
    └─ Movie1 
        └─ song1.flac 
    └─ Movie2 
        └─ song2.flac
```
---

## Audio Quality Notes

- FLAC → FLAC preserves lossless format after processing.
- MP3 → MP3 involves re-encoding and results in generation loss.
- Best practice is to keep masters in FLAC and create MP3 copies only
for portable devices or car audio systems.

---


 
