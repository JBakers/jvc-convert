# JVC Video Converter (v1.0.1)

A smart bash script for converting and merging old camcorder videos (MOD/AVI) and Milestone XProtect CCTV backups to MP4.

Current version: **v1.0.0** (semver)

## Features

- 🎥 **Supports MOD, AVI, MP4 and XProtect CCTV** files
- 📡 **Automatic XProtect extraction**
   - Detects `XProtect Files` folders (up to 3 levels deep)
   - Extracts both MJPEG and H.264 block files; skips corrupted/empty blocks gracefully
   - Uses GPU (VAAPI) when available, falls back to CPU (libx265) automatically
- 🔍 **Recursive search** in subdirectories (max 3 levels deep)
- 📅 **Smart analysis** - detects if it's a trip/vacation or separate days
- 🔧 **Automatic deinterlacing** - only when needed
- ⏱️ **Progress indicator** with estimated time remaining
- ⏭️ **Resume after interruption** - skips already converted files
- 📊 **Overview per day** with duration and file size
- 🎬 **Merge options** - per day, time of day, or all in one file
- 🖥️ **Hardware encoding** via VAAPI (Intel/AMD GPU)
   - Automatic CPU fallback; temporary extraction stored in `/tmp/jvc_xprotect_*` and cleaned up

## Requirements

- Linux (tested on Debian 13)
- ffmpeg with video codec support (libx265 for CPU, VAAPI for GPU)
- exiftool (`sudo apt install libimage-exiftool-perl`)
- bc (`sudo apt install bc`)
- (Dev only) shellcheck is optional; not required to run the script

### Optional (for faster GPU encoding)
- VAAPI support: Intel Media Driver or MESA VAAPI
- GPU: Intel or AMD processor (optional, falls back to CPU)

## Installation
```bash
# Copy to your local bin
cp jvc-convert.sh ~/.local/bin/jvc-convert
chmod +x ~/.local/bin/jvc-convert

# Make sure ~/.local/bin is in your PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Usage
```bash
# Navigate to a folder with videos
cd /path/to/videos

# Run the script
jvc-convert
```

The script analyzes the files and asks smart questions:
```
🎥 Video Converter Tool
=======================
📁 Found: 1 XProtect CCTV backup(s), 0 MOD, 0 AVI files
🔍 Analyzing files...
   📂 N files found

📡 XProtect CCTV backup(s) processing...
   📁 Export 22-11-2013 13-35-45
   ✅ Extracted

📊 Analysis result:
   📅 1 day(s)
   ⏱️  2 hours 15 min total
   💾 2.34 GB source data
```

### XProtect CCTV Support

The script now supports **Milestone XProtect CCTV backups**! When XProtect folders are detected:

1. **Automatic detection** - Finds `XProtect Files` folders at any level (up to 3 folders deep)
2. **Video extraction** - Extracts MJPEG or H.264 video from `.blk` block files; corrupt blocks are skipped
3. **Format conversion** - Converts extracted video to efficient H.265/HEVC format (VAAPI → CPU fallback)
4. **Integration** - Treats extracted videos like regular video files for merging/organizing

**XProtect folder structure:**
```
~/Video's/temp cctv/
└── Export 22-11-2013 13-35-45/
    ├── autorun.inf
    ├── SmartClient-Player.exe
    └── XProtect Files/
        ├── Client/
        ├── Data/
        │   ├── CustomSettings/
        │   ├── Mediadata/
        │   │   └── [GUID]/
        │   │       └── [Camera-ID]/
        │   │           └── block0.blk  ← Video file
        │   │           ├── pindex.idx
        │   │           └── config.xml
        │   └── ...
        └── Exported Project.scp
```

## Output

Files are saved to `~/Video's/JVC Geconverteerd/[Name] ([Date range])/`:
```
~/Video's/JVC Geconverteerd/
└── CCTV Backup November 2013 (22-11-2013)/
    ├── converted/          # Individual converted MP4s
    ├── 22-11-2013.mp4      # Merged video
   ├── *-salvage.mp4       # Optional recovered clips if manual salvage was run
    └── ...
```

## Tips

- **Interrupt**: Press `Ctrl+C` to stop. Restart with the same name to resume.
- **Subdirectories**: The script automatically searches 3 levels deep.
- **Long days**: For days with more than 30 min of video, you can split into morning/afternoon/evening.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
