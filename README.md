# JVC Video Converter

A smart bash script for converting and merging old camcorder videos (MOD/AVI) to MP4.

## Features

- 🎥 **Supports MOD, AVI and MP4** files
- 🔍 **Recursive search** in subdirectories (max 3 levels deep)
- 📅 **Smart analysis** - detects if it's a trip/vacation or separate days
- 🔧 **Automatic deinterlacing** - only when needed
- ⏱️ **Progress indicator** with estimated time remaining
- ⏭️ **Resume after interruption** - skips already converted files
- 📊 **Overview per day** with duration and file size
- 🎬 **Merge options** - per day, time of day, or all in one file
- 🖥️ **Hardware encoding** via VAAPI (Intel/AMD GPU)

## Requirements

- Linux (tested on Debian 13)
- ffmpeg with VAAPI support
- exiftool (`sudo apt install libimage-exiftool-perl`)
- bc (`sudo apt install bc`)

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
📁 Found: 231 MOD, 0 AVI files - converting
🔍 Analyzing files...
   📂 231 files found

📊 Analysis result:
   📅 18 day(s)
   ⏱️  2 hours 51 min total
   💾 11.16 GB source data
   📆 Maximum gap between days: 3 day(s)

   📋 Overview per day:
      Wed 28 Apr 2010         1 files,   1 min 21 sec
      Thu 29 Apr 2010         6 files,   4 min 32 sec
      ...

💡 This looks like a trip or vacation (18 consecutive days).

How do you want to merge?
  1) One file per day
  2) Per day, split long days into time periods
  3) Everything in one file
```

## Output

Files are saved to `~/Video's/JVC Geconverteerd/[Name] ([Date range])/`:
```
~/Video's/JVC Geconverteerd/
└── Cuba Vacation (28-04-2010 to 15-05-2010)/
    ├── converted/          # Individual converted MP4s
    ├── 28-april-2010.mp4   # Merged day
    ├── 29-april-2010.mp4
    └── ...
```

## Tips

- **Interrupt**: Press `Ctrl+C` to stop. Restart with the same name to resume.
- **Subdirectories**: The script automatically searches 3 levels deep.
- **Long days**: For days with more than 30 min of video, you can split into morning/afternoon/evening.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
