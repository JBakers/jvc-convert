# Changelog

## [1.0.8] - 2025-12-16

### Added
- **🔄 Salvage Mode** - Brute-force recovery for corrupted XProtect blocks (MJPEG/H.264/copy fallback)
- **⏳ Spinner Progress** - Visual progress indicator during long ffmpeg operations
- **🔢 Auto-versioning** - Pre-commit hook for automatic semver patch bump

### Fixed
- **Concat escaping** - Fixed path escaping for files with spaces/quotes in merge_files()
- **Pre-commit sed** - Fixed invalid regex patterns in version bump hook

### Changed
- Banner now shows dynamic version from version.txt
- Skip duplicate version bumps per commit

---

## [1.0.0] - 2025-12-15

### Added
- **🎬 Milestone XProtect CCTV Support** - Automatic detection and extraction of XProtect CCTV backup folders
  - Detects `XProtect Files` folders up to 3 levels deep
  - Automatically extracts MJPEG video from `.blk` block files (>1MB)
  - Seamlessly integrates extracted videos with MOD/AVI conversion pipeline
  - Supports multiple cameras and multiple time periods per backup

- **📡 Automatic Format Detection** - Detects MJPEG format in XProtect block files
  - FFmpeg automatically recognizes XProtect MJPEG streams
  - No manual format specification needed

- **🔄 Fallback Encoding Strategy** - More robust video encoding
  - Primary: VAAPI GPU acceleration (Intel/AMD)
  - Fallback: libx265 CPU encoding (always works, slower)
  - Last resort: Stream copy without re-encoding (fastest but may have compatibility issues)

- **🧹 Automatic Cleanup** - Temporary extraction directories are cleaned up automatically
  - XProtect extractions stored in `/tmp/jvc_xprotect_[PID]/` during processing
  - Automatically removed when script finishes

### Changed
- **Improved Error Handling** - Better reporting of empty/invalid XProtect backups
  - Shows which backups succeeded and which have no data
  - Clear messages for backup structure issues

- **Updated Documentation**
  - New `XPROTECT_GUIDE.md` with detailed CCTV conversion guide
  - Updated README with XProtect examples
  - Clarified hardware requirements (VAAPI optional, CPU fallback supported)

### Technical Details

#### XProtect Extraction Process
1. **Detection** - Finds all `XProtect Files` directories recursively
2. **Size Check** - Filters `.blk` files larger than 1MB (video data)
3. **Format Recognition** - FFmpeg auto-detects MJPEG format
4. **Encoding** - Converts to H.265/HEVC MP4 with fallback strategy:
   - GPU: VAAPI HEVC (fastest on supported hardware)
   - CPU: libx265 (compatible, slower)
   - Copy: No encoding (fastest, may have format issues)
5. **Integration** - Merged files join the normal processing pipeline

#### File Handling
- Extracted XProtect files are temporarily stored in `/tmp/jvc_xprotect_[PID]/`
- Successfully extracted files are copied to `OUTPUT_DIR/converted/`
- Temporary directory is cleaned up at script completion
- Source `.blk` files are never modified

#### Performance Notes
- MJPEG to H.265 conversion typically 2-10x faster than real-time
- Multiple backups processed in sequence (could be parallelized in future)
- GPU encoding can reduce conversion time by 50-80% on supported hardware

### Tested With
- **Hardware**: Debian 13, Intel/AMD CPUs
- **XProtect Backups**: Milestone XProtect export folders with multiple cameras
- **File Sizes**: Tested with 23 block files (total 1.7GB backup)
- **Encoding**: MJPEG video (standard for XProtect CCTV systems)

### Known Limitations
- Only works with XProtect's standard MJPEG export format
- Some older XProtect systems may use different compression (untested)
- Block files smaller than 1MB are skipped (assumed to be metadata/index files)

## [1.0.0] - Previous Release
- Original support for MOD, AVI, and MP4 files
- Hardware-accelerated H.265 encoding via VAAPI
- Smart analysis (vacation/trip detection, consecutive days)
- Merge options (per day, time-of-day splits, single file)
- Automatic deinterlacing detection
