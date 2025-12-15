# Milestone XProtect CCTV Conversion Guide

## Quick Start

1. Navigate to the folder containing XProtect CCTV backups:
   ```bash
   cd ~/Video's/temp\ cctv/
   ```

2. Run the converter:
   ```bash
   ~/Workspace/jvc-convert/jvc-convert.sh
   ```

3. Follow the prompts - the script will:
   - ✅ Detect all XProtect CCTV backup folders
   - ✅ Extract video from `.blk` files
   - ✅ Convert to efficient H.265/HEVC MP4
   - ✅ Organize by date and time

## What Gets Converted

### Input
- **Location**: `XProtect Files/Data/Mediadata/*/*/block0.blk` (and block1, block2, etc.)
- **Format**: Binary MPEG video frames in .blk container
- **Typically contains**: Continuous CCTV footage from cameras

### Output
- **Format**: H.265/HEVC codec in MP4 container
- **Location**: `~/Video's/JVC Geconverteerd/[Name] ([Date range])/`
- **Benefits**: 
  - 50-60% smaller file size than original
  - Modern, widely compatible format
  - Hardware accelerated encoding (fast)

## Typical Workflow

```
~/Video's/temp cctv/
├── Export 22-11-2013 13-35-45/
│   └── XProtect Files/
│       └── Data/Mediadata/[GUID]/[Camera]/block0.blk
├── Export 3-12-2013 14-46-08/
│   └── XProtect Files/
│       └── Data/Mediadata/[GUID]/[Camera]/block0.blk
└── ... (more backups)

                    ↓ (script processes)
                    
~/Video's/JVC Geconverteerd/
└── CCTV Archief (22-11-2013 to 03-12-2013)/
    ├── converted/
    │   ├── xprotect_0.mp4  (camera 1 - time period 1)
    │   ├── xprotect_1.mp4  (camera 1 - time period 2)
    │   └── ...
    ├── 22-november-2013.mp4  (merged day 1)
    ├── 23-november-2013.mp4  (merged day 2)
    └── ...
```

## File Organization

### Single Camera, Multiple Time Periods
If a camera recorded for a long time (>30 min), the script asks:
- **Option 1**: Per day (one file per calendar day)
- **Option 2**: Per time period (morning/afternoon/evening split)
- **Option 3**: One large file for everything

### Multiple Cameras
If multiple cameras were backed up, each gets its own conversion:
- **Camera 1 block files** → `xprotect_0.mp4`, `xprotect_1.mp4`, ...
- **Camera 2 block files** → `xprotect_2.mp4`, `xprotect_3.mp4`, ...

Then they can be merged per day or kept separate.

## Technical Details

### MPEG Extraction
- XProtect stores video in `.blk` files as MPEG-1/MPEG-2 streams
- The script uses `ffmpeg` to read and re-encode these frames
- Deinterlacing is applied (XProtect often uses interlaced video)

### Hardware Acceleration
- Uses VAAPI (Video Acceleration API)
- GPU device: `/dev/dri/renderD128` (Intel/AMD)
- Codec: H.265/HEVC
- Quality: Medium (qp 26) - good balance of quality/speed

### Performance
- Typically converts at 30-120 fps (real-time or faster)
- A 2-hour XProtect video usually converts in 1-10 minutes
- Can resume if interrupted

## Troubleshooting

### "No files found" in Analysis
**Cause**: XProtect backup structure is missing `.blk` files
**Solution**: 
- Verify you're in the correct directory
- Check that `XProtect Files/Data/Mediadata/` folders exist
- Some backups might be corrupted or not contain video data

### Converted files are very small or won't play
**Cause**: ffmpeg couldn't extract valid video from `.blk` files
**Solution**:
- The `.blk` file might be in a different format
- Try manual inspection: `ffprobe XProtect\ Files/Data/Mediadata/*/*/block0.blk`
- Some XProtect systems use proprietary compression

### Slow conversion
**Cause**: VAAPI hardware acceleration not available
**Solution**:
- Check if VAAPI device exists: `ls -la /dev/dri/renderD128`
- Install `intel-media-driver` or `libva-mesa-driver`
- Script will fall back to CPU (much slower)

## Advanced Options

### Manual Extraction
To extract just one camera without merging:
```bash
ffmpeg -i ~/Video's/temp\ cctv/Export\ 22-11-2013\ 13-35-45/XProtect\ Files/Data/Mediadata/*/*/block0.blk \
  -c:v hevc_vaapi -qp 26 \
  -c:a aac -b:a 192k \
  output.mp4
```

### Check Original MPEG Info
```bash
ffprobe ~/Video's/temp\ cctv/Export\ 22-11-2013\ 13-35-45/XProtect\ Files/Data/Mediadata/*/*/block0.blk
```

## Next Steps

After conversion:
1. ✅ Verify output files play correctly
2. ✅ Clean up (script offers to delete source files)
3. ✅ Archive to external storage or cloud
4. ✅ Delete temporary files to save space

---

**Questions?** Check the main [README.md](README.md) or examine `jvc-convert.sh` directly.
