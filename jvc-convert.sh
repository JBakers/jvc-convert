#!/bin/bash
# jvc-convert - Video's converteren en samenvoegen (MOD/AVI/MP4)

shopt -s nullglob

INPUT_DIR="."
BASE_DIR="$HOME/Video's/JVC Geconverteerd"

echo "🎥 Video Converter Tool"
echo "======================="

# Check bestanden (recursief, max 3 diep)
mod_count=$(find "$INPUT_DIR" -maxdepth 3 -type f -iname "*.MOD" 2>/dev/null | wc -l)
avi_count=$(find "$INPUT_DIR" -maxdepth 3 -type f -iname "*.avi" 2>/dev/null | wc -l)
mp4_count=$(find "$INPUT_DIR" -maxdepth 3 -type f -iname "*.mp4" 2>/dev/null | wc -l)

# Check voor XProtect mappen
xprotect_count=$(find "$INPUT_DIR" -maxdepth 3 -type d -name "XProtect Files" 2>/dev/null | wc -l)

total_source=$((mod_count + avi_count + xprotect_count))

if [ "$xprotect_count" -gt 0 ]; then
    echo "📁 Gevonden: $xprotect_count XProtect CCTV backup(s), $mod_count MOD, $avi_count AVI bestanden"
    MODE="convert"
    # Telt niet verder mee; verwijderd om shellcheck ruis te voorkomen
elif [ "$total_source" -gt 0 ]; then
    echo "📁 Gevonden: $mod_count MOD, $avi_count AVI bestanden - gaan converteren"
    MODE="convert"
elif [ "$mp4_count" -gt 0 ]; then
    echo "📁 Gevonden: $mp4_count MP4 bestanden - gaan samenvoegen"
    MODE="merge"
else
    echo "❌ Geen MOD, AVI, MP4 of XProtect bestanden gevonden"
    exit 1
fi

# Functie om te checken of deinterlacing nodig is
needs_deinterlace() {
    local file="$1"
    local field_order
    field_order=$(ffprobe -v error -select_streams v:0 -show_entries stream=field_order -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    
    case "$field_order" in
        tt|bb|tb|bt) return 0 ;;
        *) return 1 ;;
    esac
}

# Functie om datum uit bestand te halen
get_file_date() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    local date_str=""
    
    if [[ "$filename" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_ ]]; then
        date_str="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        date_str="${BASH_REMATCH[1]}"
    fi
    
    if [ -z "$date_str" ]; then
        local moi_file="${file%.MOD}.MOI"
        [ -f "$moi_file" ] && date_str=$(exiftool -s3 -DateTimeOriginal "$moi_file" 2>/dev/null | sed 's/\([0-9]\{4\}\):\([0-9]\{2\}\):\([0-9]\{2\}\).*/\1-\2-\3/')
    fi
    
    if [ -z "$date_str" ]; then
        date_str=$(exiftool -s3 -FileModifyDate "$file" 2>/dev/null | sed 's/\([0-9]\{4\}\):\([0-9]\{2\}\):\([0-9]\{2\}\).*/\1-\2-\3/')
    fi
    
    echo "$date_str"
}

# Functie om tijd uit bestand te halen
get_file_time() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    local time_str=""
    
    if [[ "$filename" =~ ^[0-9]{8}_([0-9]{2})([0-9]{2}) ]]; then
        time_str="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    elif [[ "$filename" =~ _([0-9]{2})([0-9]{2})_ ]]; then
        time_str="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    fi
    
    if [ -z "$time_str" ]; then
        time_str=$(exiftool -s3 -FileModifyDate "$file" 2>/dev/null | sed 's/.*\([0-9]\{2\}\):\([0-9]\{2\}\):[0-9]\{2\}.*/\1:\2/')
    fi
    
    echo "$time_str"
}

# Functie om dagdeel te bepalen
get_dagdeel() {
    local time_str="$1"
    local hour="${time_str%%:*}"
    hour=$((10#$hour))
    
    if [ "$hour" -lt 12 ]; then
        echo "ochtend"
    elif [ "$hour" -lt 18 ]; then
        echo "middag"
    else
        echo "avond"
    fi
}

# Functie om video duur in seconden te krijgen
get_duration() {
    local file="$1"
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d. -f1
}

# Eenvoudige spinner voor lange taken
run_with_spinner() {
    local msg="$1"; shift
    local spinner='|/-\\'
    local i=0
    printf "%s " "$msg"
    "$@" &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s %s" "$msg" "${spinner:i++%4:1}"
        sleep 0.2
    done
    wait "$pid"
    local status=$?
    printf "\r%s %s\n" "$msg" "$([ $status -eq 0 ] && echo '✅' || echo '❌')"
    return $status
}

# Functie om XProtect CCTV backup te verwerken
extract_xprotect() {
    local xprotect_dir="$1"
    local output_dir="$2"
    
    if [ ! -d "$xprotect_dir" ]; then
        return 1
    fi
    
    # Zoek .blk bestanden die groot genoeg zijn voor video (>1MB)
    local video_blk_files=()
    while IFS= read -r blk; do
        [ -f "$blk" ] && video_blk_files+=("$blk")
    done < <(find "$xprotect_dir" -type f -name "*.blk" -size +1M 2>/dev/null | sort)
    
    # Geen grote .blk bestanden = waarschijnlijk leeg backup
    if [ ${#video_blk_files[@]} -eq 0 ]; then
        return 1
    fi
    
    # XProtect blokbestanden kunnen verschillende formaten bevatten:
    # - MJPEG (Motion JPEG) - meest gebruikelijk
    # - H.264 - sommige moderne systemen
    # - Proprietary containers - mogelijk niet decodeerbaar
    local extracted_count=0
    local blk_idx=0
    local skip_count=0
    
    for blk_file in "${video_blk_files[@]}"; do
        local output_file="$output_dir/xprotect_${blk_idx}.mp4"
        
        # Skip als al geconverteerd
        [ -f "$output_file" ] && { ((blk_idx++)); continue; }
        
        # Probeer VAAPI GPU encoding eerst (timeout 30s voor veiligheid)
        if timeout 30 ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
            -i "$blk_file" \
            -c:v hevc_vaapi -qp 26 \
            -c:a aac -b:a 192k \
            "$output_file" -y -v error -stats < /dev/null 2>/dev/null; then
            
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                ((extracted_count++))
                ((blk_idx++))
                continue
            else
                rm -f "$output_file"
            fi
        fi
        
        # Fallback naar CPU encoding (libx265) - timeout 60s
        if timeout 60 ffmpeg -i "$blk_file" \
            -c:v libx265 -crf 26 \
            -c:a aac -b:a 192k \
            "$output_file" -y -v error -stats < /dev/null 2>/dev/null; then
            
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                ((extracted_count++))
                ((blk_idx++))
                continue
            else
                rm -f "$output_file"
            fi
        fi
        
        # Laatste fallback: copy streams zonder re-encoding (timeout 30s)
        if timeout 30 ffmpeg -i "$blk_file" \
            -c:v copy -c:a aac -b:a 192k \
            "$output_file" -y -v error < /dev/null 2>/dev/null; then
            
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                ((extracted_count++))
                ((blk_idx++))
                continue
            else
                rm -f "$output_file"
            fi
        fi
        
        # Bestand kon niet worden gedecodeerd (korrupt, onbekend formaat, permissies, etc.)
        ((skip_count++))
        ((blk_idx++))
    done
    
    # Return success als we minstens 1 bestand hebben geëxtraheerd
    # Sommige XProtect backups kunnen partially corrupted zijn
    return $((extracted_count > 0 ? 0 : 1))
}

# Functie om minuten naar leesbare tijd te converteren
format_duration() {
    local minutes=$1
    if [ "$minutes" -ge 60 ]; then
        echo "$((minutes / 60)) uur $((minutes % 60)) min"
    else
        echo "${minutes} min"
    fi
}

# Functie om te checken of dagen aaneengesloten zijn
check_consecutive_days() {
    local -a dates=("$@")
    local prev_date=""
    local max_gap=0
    
    for date in "${dates[@]}"; do
        if [ -n "$prev_date" ]; then
            local prev_epoch
            prev_epoch=$(date -d "$prev_date" +%s 2>/dev/null)
            local curr_epoch
            curr_epoch=$(date -d "$date" +%s 2>/dev/null)
            local gap=$(( (curr_epoch - prev_epoch) / 86400 ))
            [ "$gap" -gt "$max_gap" ] && max_gap=$gap
        fi
        prev_date="$date"
    done
    
    echo "$max_gap"
}

# Functie om slimme naam te genereren
generate_name() {
    local -a dates=("$@")
    
    if [ ${#dates[@]} -eq 0 ]; then
        echo "video"
        return
    fi
    
    local sorted_dates
    mapfile -t sorted_dates < <(printf '%s\n' "${dates[@]}" | sort -u)
    local first_date="${sorted_dates[0]}"
    local last_date="${sorted_dates[-1]}"
    
    local first_year="${first_date:0:4}"
    local first_month="${first_date:5:2}"
    local first_day="${first_date:8:2}"
    local last_year="${last_date:0:4}"
    local last_month="${last_date:5:2}"
    local last_day="${last_date:8:2}"
    
    local months=('' 'januari' 'februari' 'maart' 'april' 'mei' 'juni' 'juli' 'augustus' 'september' 'oktober' 'november' 'december')
    
    if [ "$first_date" == "$last_date" ]; then
        echo "${first_day}-${months[${first_month#0}]}-${first_year}"
    elif [ "$first_year" != "$last_year" ]; then
        echo "${first_year}-${last_year}"
    elif [ "$first_month" != "$last_month" ]; then
        echo "${months[${first_month#0}]}-${months[${last_month#0}]}-${first_year}"
    else
        local first_week=$(( (10#$first_day - 1) / 7 + 1 ))
        local last_week=$(( (10#$last_day - 1) / 7 + 1 ))
        
        if [ "$first_week" == "$last_week" ]; then
            echo "week${first_week}-${months[${first_month#0}]}-${first_year}"
        else
            echo "${first_day}-${last_day}-${months[${first_month#0}]}-${first_year}"
        fi
    fi
}

# Functie om MP4's samen te voegen
merge_files() {
    local output_path="$1"
    shift
    local -a files=("$@")
    
    local tmpfile
    tmpfile=$(mktemp /tmp/filelist_XXXX.txt)
    rm -f "$tmpfile" && tmpfile=$(mktemp /tmp/filelist_XXXX.txt)
    
    for file in "${files[@]}"; do
        # Zorg voor absoluut pad
        local abs_file
        abs_file=$(realpath "$file" 2>/dev/null || echo "$file")
        # Gebruik %q zodat spaties en quotes veilig zijn in concat file
        printf "file %q\n" "$abs_file" >> "$tmpfile"
    done
    
    if [ -s "$tmpfile" ]; then
        run_with_spinner "   🔗 Samenvoegen..." ffmpeg -f concat -safe 0 -i "$tmpfile" -c copy "$output_path" -y -v error -stats
        local result=$?
        rm -f "$tmpfile"
        return $result
    fi
    rm -f "$tmpfile"
    return 1
}

# Arrays voor data
declare -A files_by_date
declare -A files_by_date_dagdeel
declare -A duration_by_date
declare -a all_dates

echo ""
echo "🔍 Bestanden analyseren..."

# Eerst XProtect CCTV backups verwerken (als aanwezig)
xprotect_dirs=()
while IFS= read -r xp_dir; do
    [ -d "$xp_dir" ] && xprotect_dirs+=("$xp_dir")
done < <(find "$INPUT_DIR" -maxdepth 3 -type d -name "XProtect Files" 2>/dev/null)

xprotect_extracted=0
temp_convert_dir=""
if [ ${#xprotect_dirs[@]} -gt 0 ]; then
    echo "   📡 XProtect CCTV backup(s) verwerken..."
    temp_convert_dir="/tmp/jvc_xprotect_$$"
    mkdir -p "$temp_convert_dir"
    
    for xp_dir in "${xprotect_dirs[@]}"; do
        xp_name=$(basename "$(dirname "$xp_dir")")
        echo "      📁 $xp_name"
        if extract_xprotect "$xp_dir" "$temp_convert_dir"; then
            ((xprotect_extracted++))
            echo "         ✅ Videobestanden geëxtraheerd"
        else
            echo "         ⚠️  Geen videodata gevonden in deze backup"
        fi
    done
    
    if [ "$xprotect_extracted" -gt 0 ]; then
        echo ""
    else
        # Geen succesvolle extracties
        rm -rf "$temp_convert_dir"
        temp_convert_dir=""
    fi
fi

# Verzamel alle bronbestanden (recursief, max 3 diep)
source_files=()
while IFS= read -r f; do
    [ -f "$f" ] && source_files+=("$f")
done < <((find "$INPUT_DIR" -maxdepth 3 -type f \( -iname "*.MOD" -o -iname "*.avi" -o -iname "*.mp4" \) 2>/dev/null; [ -n "$temp_convert_dir" ] && find "$temp_convert_dir" -maxdepth 1 -type f -iname "*.mp4" 2>/dev/null) | sort)

echo "   📂 ${#source_files[@]} bestanden gevonden"

# Analyseer bestanden en verzamel datums + duur
total_duration_sec=0
for file in "${source_files[@]}"; do
    just_date=$(get_file_date "$file")
    dur=$(get_duration "$file")
    [ -z "$dur" ] && dur=0
    
    total_duration_sec=$((total_duration_sec + dur))
    
    if [ -n "$just_date" ]; then
        all_dates+=("$just_date")
        duration_by_date["$just_date"]=$((${duration_by_date["$just_date"]:-0} + dur))
    fi
done

# Bepaal statistieken
mapfile -t unique_dates < <(printf '%s\n' "${all_dates[@]}" | sort -u)
num_days=${#unique_dates[@]}
total_minutes=$((total_duration_sec / 60))
max_gap=$(check_consecutive_days "${unique_dates[@]}")

# Bepaal langste dag
longest_day_minutes=0
# shellcheck disable=SC2034 # wordt later gebruikt voor suggesties over lange dag
longest_day=""
for date in "${!duration_by_date[@]}"; do
    day_min=$((${duration_by_date[$date]} / 60))
    if [ "$day_min" -gt "$longest_day_minutes" ]; then
        longest_day_minutes=$day_min
        # shellcheck disable=SC2034
        longest_day=$date
    fi
done

# Bereken totale bestandsgrootte
total_size_bytes=0
for file in "${source_files[@]}"; do
    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    total_size_bytes=$((total_size_bytes + size))
done
total_size_gb=$(echo "scale=2; $total_size_bytes / 1073741824" | bc)
total_size_mb=$(echo "scale=0; $total_size_bytes / 1048576" | bc)

# Tel bestanden per dag (hergebruik all_dates array)
declare -A files_count_by_date
for date in "${all_dates[@]}"; do
    files_count_by_date["$date"]=$((${files_count_by_date["$date"]:-0} + 1))
done

echo ""
echo "📊 Analyse resultaat:"
echo "   📅 $num_days dag(en)"
echo "   ⏱️  $(format_duration $total_minutes) totaal"
if [ "$total_size_mb" -ge 1024 ]; then
    echo "   💾 ${total_size_gb} GB brondata"
else
    echo "   💾 ${total_size_mb} MB brondata"
fi
[ "$num_days" -gt 1 ] && echo "   📆 Maximale gap tussen dagen: $max_gap dag(en)"
echo ""
echo "   📋 Overzicht per dag:"
for date in "${unique_dates[@]}"; do
    day_min=$((${duration_by_date[$date]} / 60))
    day_sec=$((${duration_by_date[$date]} % 60))
    day_file_count=${files_count_by_date[$date]:-0}
    readable_date=$(date -d "$date" +"%a %d %b %Y" 2>/dev/null || echo "$date")
    printf "      %-20s %3d bestanden, %3d min %02d sec\n" "$readable_date" "$day_file_count" "$day_min" "$day_sec"
done

# Bepaal scenario en stel vragen
echo ""

if [ "$num_days" -eq 1 ] && [ "$total_minutes" -le 30 ]; then
    echo "💡 Dit is een korte opname van één dag."
    MERGE_MODE="alles"
    USE_DAGDELEN=false
    
elif [ "$num_days" -eq 1 ] && [ "$total_minutes" -gt 30 ]; then
    echo "💡 Dit is één dag met $(format_duration $total_minutes) aan video."
    echo ""
    echo "Hoe wil je samenvoegen?"
    echo "  1) Per dagdeel (ochtend/middag/avond)"
    echo "  2) Eén bestand per dag"
    echo "  3) Niet samenvoegen (alleen converteren)"
    echo ""
    read -p "Keuze [1/2/3]: " choice
    
    case $choice in
        1) MERGE_MODE="per_dag"; USE_DAGDELEN=true ;;
        2) MERGE_MODE="alles"; USE_DAGDELEN=false ;;
        3) MERGE_MODE="geen"; USE_DAGDELEN=false ;;
        *) MERGE_MODE="alles"; USE_DAGDELEN=false ;;
    esac

elif [ "$num_days" -gt 1 ] && [ "$max_gap" -le 7 ]; then
    echo "💡 Dit lijkt op een reis of vakantie ($num_days aaneengesloten dagen)."
    echo ""
    echo "Hoe wil je samenvoegen?"
    echo "  1) Eén bestand per dag"
    if [ "$longest_day_minutes" -gt 30 ]; then
        echo "  2) Per dag, lange dagen opdelen in dagdelen"
        echo "  3) Alles in één bestand"
    else
        echo "  2) Alles in één bestand"
    fi
    echo ""
    read -p "Keuze: " choice
    
    if [ "$longest_day_minutes" -gt 30 ]; then
        case $choice in
            1) MERGE_MODE="per_dag"; USE_DAGDELEN=false ;;
            2) MERGE_MODE="per_dag"; USE_DAGDELEN=true ;;
            3) MERGE_MODE="alles"; USE_DAGDELEN=false ;;
            *) MERGE_MODE="per_dag"; USE_DAGDELEN=false ;;
        esac
    else
        case $choice in
            1) MERGE_MODE="per_dag"; USE_DAGDELEN=false ;;
            2) MERGE_MODE="alles"; USE_DAGDELEN=false ;;
            *) MERGE_MODE="per_dag"; USE_DAGDELEN=false ;;
        esac
    fi

elif [ "$num_days" -gt 1 ] && [ "$max_gap" -gt 7 ]; then
    echo "💡 Dit zijn $num_days losse dagen verspreid over langere periode."
    echo "   → Per dag samenvoegen (logisch voor losse momenten)"
    echo ""
    
    if [ "$longest_day_minutes" -gt 30 ]; then
        echo "Er zijn dagen met meer dan 30 minuten video."
        echo "Wil je lange dagen opdelen in dagdelen?"
        echo "  1) Ja"
        echo "  2) Nee"
        echo ""
        read -p "Keuze [1/2]: " choice
        [ "$choice" == "1" ] && USE_DAGDELEN=true || USE_DAGDELEN=false
    else
        USE_DAGDELEN=false
    fi
    MERGE_MODE="per_dag"
fi

# Vraag naam voor deze collectie
echo ""
read -p "📝 Geef deze collectie een naam (bijv. 'Cuba vakantie' of 'Wintersport'): " COLLECTIE_NAAM

if [ -z "$COLLECTIE_NAAM" ]; then
    COLLECTIE_NAAM="Video's $(date +%Y-%m-%d)"
fi

# Bepaal datum-range voor mapnaam
if [ ${#unique_dates[@]} -gt 0 ]; then
    first_date="${unique_dates[0]}"
    last_date="${unique_dates[-1]}"
    
    first_formatted=$(date -d "$first_date" +"%d-%m-%Y" 2>/dev/null || echo "$first_date")
    last_formatted=$(date -d "$last_date" +"%d-%m-%Y" 2>/dev/null || echo "$last_date")
    
    if [ "$first_date" == "$last_date" ]; then
        DATE_RANGE="$first_formatted"
    else
        DATE_RANGE="${first_formatted} tot ${last_formatted}"
    fi
else
    DATE_RANGE=$(date +%d-%m-%Y)
fi

# Maak output mappen
FINAL_DIR="$BASE_DIR/$COLLECTIE_NAAM ($DATE_RANGE)"
OUTPUT_DIR="$FINAL_DIR/converted"
mkdir -p "$OUTPUT_DIR"

# Kopie geëxtraheerde XProtect bestanden naar output dir
if [ -n "$temp_convert_dir" ] && [ -d "$temp_convert_dir" ]; then
    cp "$temp_convert_dir"/*.mp4 "$OUTPUT_DIR/" 2>/dev/null
fi

echo ""
echo "📂 Output: $FINAL_DIR"
echo "📦 Modus: $MERGE_MODE$([ "$USE_DAGDELEN" == true ] && echo " (met dagdelen)")"
echo ""

# Converteer indien nodig
if [ "$MODE" == "convert" ]; then
    echo "🔄 Converteren..."
    echo ""
    
    # Tel alleen te converteren bestanden (geen MP4's)
    convert_total=0
    for file in "${source_files[@]}"; do
        [[ ! "$file" =~ \.(mp4|MP4)$ ]] && ((convert_total++))
    done
    
    convert_done=0
    convert_skipped=0
    total_convert_time=0
    
    for file in "${source_files[@]}"; do
        [[ "$file" =~ \.(mp4|MP4)$ ]] && continue
        
        base_name=$(basename "$file")
        base_name="${base_name%.*}"
        
        just_date=$(get_file_date "$file")
        just_time=$(get_file_time "$file")
        dagdeel=$(get_dagdeel "$just_time")
        
        [ -z "$just_date" ] && just_date="onbekend"
        
        # Bepaal extension
        ext="${file##*.}"
        [[ "$ext" =~ ^(mpg|MPEG|mpeg)$ ]] && ext="mp4"  # MPG/MPEG converteren naar MP4
        
        output_name="${just_date}_${just_time//:/}_${base_name}.${ext,,}"
        output_name="${output_name// /_}"
        
        # Progress indicator
        remaining=$((convert_total - convert_done - convert_skipped))
        echo "📹 [$((convert_done + convert_skipped + 1))/$convert_total] $(basename "$file")"
        
        # Skip als al geconverteerd
        if [ -f "$OUTPUT_DIR/$output_name" ]; then
            echo "   ⏭️  Al geconverteerd, overslaan"
            output_full=$(realpath "$OUTPUT_DIR/$output_name")
            files_by_date["$just_date"]+="$output_full"$'\n'
            files_by_date_dagdeel["${just_date}_${dagdeel}"]+="$output_full"$'\n'
            ((convert_skipped++))
            continue
        fi
        
        # Tijd schatting
        if [ "$convert_done" -gt 0 ]; then
            avg_time=$((total_convert_time / convert_done))
            eta_seconds=$((avg_time * remaining))
            eta_min=$((eta_seconds / 60))
            eta_sec=$((eta_seconds % 60))
            echo "   ⏱️  Geschatte resttijd: ${eta_min}m ${eta_sec}s ($remaining bestanden)"
        fi
        
        echo "   📅 $just_date $just_time ($dagdeel)"
        
        # Check of deinterlacing nodig is (skip voor MPG/MPEG files geëxtraheerd van XProtect)
        if [[ "$file" =~ \.(mpg|mpeg|MPG|MPEG)$ ]]; then
            echo "   🔧 Deinterlacing: auto (XProtect MPEG)"
            vf_opts="yadif=1,format=nv12,hwupload"
        elif needs_deinterlace "$file"; then
            echo "   🔧 Deinterlacing: ja"
            vf_opts="yadif=1,format=nv12,hwupload"
        else
            echo "   🔧 Deinterlacing: nee"
            vf_opts="format=nv12,hwupload"
        fi
        
        # Start timer
        start_time=$(date +%s)
        
        # Converteer
        ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
            -i "$file" \
            -vf "$vf_opts" \
            -c:v hevc_vaapi -qp 26 \
            -c:a aac -b:a 192k \
            "$OUTPUT_DIR/$output_name" \
            -y -v error -stats
        
        convert_result=$?
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        total_convert_time=$((total_convert_time + elapsed))
        
        if [ $convert_result -eq 0 ]; then
            echo "   ✅ (${elapsed}s)"
            output_full=$(realpath "$OUTPUT_DIR/$output_name")
            files_by_date["$just_date"]+="$output_full"$'\n'
            files_by_date_dagdeel["${just_date}_${dagdeel}"]+="$output_full"$'\n'
            ((convert_done++))
        else
            echo "   ❌"
        fi
        echo ""
    done
    
    echo "📊 Conversie klaar: $convert_done geconverteerd, $convert_skipped overgeslagen"
    echo ""
    
    MP4_SOURCE="$OUTPUT_DIR"
else
    # Bestaande MP4's analyseren
    for mp4_file in "${source_files[@]}"; do
        [[ ! "$mp4_file" =~ \.(mp4|MP4)$ ]] && continue
        
        full_path=$(realpath "$mp4_file")
        just_date=$(get_file_date "$mp4_file")
        just_time=$(get_file_time "$mp4_file")
        dagdeel=$(get_dagdeel "$just_time")
        
        [ -z "$just_date" ] && just_date="onbekend"
        
        files_by_date["$just_date"]+="$full_path"$'\n'
        files_by_date_dagdeel["${just_date}_${dagdeel}"]+="$full_path"$'\n'
    done
    MP4_SOURCE="$INPUT_DIR"
fi

echo ""
echo "🔗 Samenvoegen..."
echo ""

if [ "$MERGE_MODE" == "geen" ]; then
    echo "  ⏭️  Samenvoegen overgeslagen"
elif [ "$MERGE_MODE" == "alles" ]; then
    final_name=$(generate_name "${unique_dates[@]}")
    echo "  📦 Alles → ${final_name}.mp4"
    
    mapfile -t all_files < <(find "$MP4_SOURCE" -maxdepth 1 -type f -iname "*.mp4" 2>/dev/null | sort)
    
    if merge_files "$FINAL_DIR/${final_name}.mp4" "${all_files[@]}"; then
        echo "     ✅"
    else
        echo "     ❌"
    fi
else
    for date in $(echo "${!files_by_date[@]}" | tr ' ' '\n' | sort); do
        mapfile -t day_files < <(echo -n "${files_by_date[$date]}" | sort)
        
        [ ${#day_files[@]} -eq 0 ] && continue
        
        # Bereken duur van deze dag
        day_duration=0
        for f in "${day_files[@]}"; do
            dur=$(get_duration "$f")
            day_duration=$((day_duration + dur))
        done
        day_minutes=$((day_duration / 60))
        
        day_name=$(generate_name "$date")
        
        if [ "$USE_DAGDELEN" == true ] && [ "$day_minutes" -gt 30 ]; then
            echo "  📅 $date ($(format_duration $day_minutes)) → opdelen per dagdeel"
            
            for dagdeel in ochtend middag avond; do
                mapfile -t dagdeel_files < <(echo -n "${files_by_date_dagdeel["${date}_${dagdeel}"]}" | sort)
                
                [ ${#dagdeel_files[@]} -eq 0 ] && continue
                
                output_name="${day_name}-${dagdeel}"
                echo "     🕐 ${dagdeel} (${#dagdeel_files[@]} bestanden) → ${output_name}.mp4"
                
                if merge_files "$FINAL_DIR/${output_name}.mp4" "${dagdeel_files[@]}"; then
                    echo "        ✅"
                else
                    echo "        ❌"
                fi
            done
        else
            echo "  📅 $date (${#day_files[@]} bestanden, $(format_duration $day_minutes)) → ${day_name}.mp4"
            
            if merge_files "$FINAL_DIR/${day_name}.mp4" "${day_files[@]}"; then
                echo "     ✅"
            else
                echo "     ❌"
            fi
        fi
    done
fi

# === POST-PROCESSING: Kleine bestanden combineren ===
echo ""
echo "🔍 Analyseren van resultaten..."

# Vind kleine bestanden (< 100MB)
small_files=()
small_dates=()
while IFS= read -r mp4file; do
    [ -f "$mp4file" ] || continue
    [[ "$mp4file" == */converted/* ]] && continue
    
    size=$(stat -c%s "$mp4file" 2>/dev/null || echo 0)
    size_mb=$((size / 1048576))
    
    if [ "$size_mb" -lt 100 ]; then
        small_files+=("$mp4file")
        # Extract datum uit bestandsnaam
        basename_file=$(basename "$mp4file" .mp4)
        small_dates+=("$basename_file")
    fi
done < <(find "$FINAL_DIR" -maxdepth 1 -name "*.mp4" | sort)

if [ ${#small_files[@]} -gt 1 ]; then
    echo ""
    echo "📊 Kleine bestanden gevonden (< 100MB):"
    for i in "${!small_files[@]}"; do
        size=$(stat -c%s "${small_files[$i]}" 2>/dev/null || echo 0)
        size_mb=$((size / 1048576))
        echo "   ${small_dates[$i]} (${size_mb} MB)"
    done
    
    echo ""
    echo "Wil je kleine/korte dagen samenvoegen met aangrenzende dagen?"
    echo "  1) Ja, combineer kleine bestanden"
    echo "  2) Nee, laat zoals het is"
    echo ""
    read -p "Keuze [1/2]: " combine_choice
    
    if [ "$combine_choice" == "1" ]; then
        echo ""
        echo "🔗 Kleine bestanden combineren..."
        
        # Groepeer opeenvolgende kleine bestanden
        # Simpele aanpak: combineer alle kleine bestanden die binnen 2 dagen van elkaar liggen
        
        all_mp4s=()
        while IFS= read -r mp4file; do
            [ -f "$mp4file" ] || continue
            [[ "$mp4file" == */converted/* ]] && continue
            all_mp4s+=("$mp4file")
        done < <(find "$FINAL_DIR" -maxdepth 1 -name "*.mp4" | sort)
        
        # Maak groepen van kleine + aangrenzende bestanden
        declare -a current_group=()
        declare -a groups_to_merge=()
        
        for mp4file in "${all_mp4s[@]}"; do
            size=$(stat -c%s "$mp4file" 2>/dev/null || echo 0)
            size_mb=$((size / 1048576))
            
            if [ "$size_mb" -lt 100 ]; then
                current_group+=("$mp4file")
            else
                if [ ${#current_group[@]} -gt 1 ]; then
                    # Sla groep op om te mergen
                    groups_to_merge+=("$(IFS='|'; echo "${current_group[*]}")")
                fi
                current_group=()
            fi
        done
        
        # Check laatste groep
        if [ ${#current_group[@]} -gt 1 ]; then
            groups_to_merge+=("$(IFS='|'; echo "${current_group[*]}")")
        fi
        
        # Merge elke groep
        for group in "${groups_to_merge[@]}"; do
            IFS='|' read -ra group_files <<< "$group"
            
            # Bepaal eerste en laatste datum voor naamgeving
            first_file=$(basename "${group_files[0]}" .mp4)
            last_file=$(basename "${group_files[-1]}" .mp4)
            
            # Nieuwe naam
            if [ "$first_file" == "$last_file" ]; then
                new_name="$first_file"
            else
                # Extract dag en maand uit eerste en laatste
                # Formaat: DD-maand-YYYY
                first_day=$(echo "$first_file" | grep -oP '^\d+')
                last_day=$(echo "$last_file" | grep -oP '^\d+')
                rest=$(echo "$first_file" | sed 's/^[0-9]*-//')
                new_name="${first_day}-${last_day}-${rest}"
            fi
            
            echo "   📦 Combineren: ${first_file} t/m ${last_file} → ${new_name}.mp4"
            
            # Maak filelist
            tmpfile="/tmp/combine_$$.txt"
            rm -f "$tmpfile"
            for f in "${group_files[@]}"; do
                escaped=$(echo "$f" | sed "s/'/'\\\\''/g")
                echo "file '$escaped'" >> "$tmpfile"
            done
            
            # Combineer
            ffmpeg -f concat -safe 0 -i "$tmpfile" -c copy "$FINAL_DIR/${new_name}_combined.mp4" -y -v error -stats
            
            if [ $? -eq 0 ]; then
                echo "      ✅"
                # Verwijder originele kleine bestanden
                for f in "${group_files[@]}"; do
                    rm -f "$f"
                done
                # Hernoem combined
                mv "$FINAL_DIR/${new_name}_combined.mp4" "$FINAL_DIR/${new_name}.mp4"
            else
                echo "      ❌"
                rm -f "$FINAL_DIR/${new_name}_combined.mp4"
            fi
            
            rm -f "$tmpfile"
        done
    fi
fi

# === CLEANUP OPTIES ===
echo ""
echo "🧹 Opruimen"
echo ""

# Optie 1: Converted map verwijderen
converted_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
[ -z "$converted_size" ] && converted_size="0"
echo "De converted map bevat losse MP4's ($converted_size)"
echo "   📂 $OUTPUT_DIR"
echo ""
echo "Wil je de converted map verwijderen?"
echo "  1) Ja, verwijder converted map"
echo "  2) Nee, behouden"
echo ""
read -p "Keuze [1/2]: " cleanup_converted

if [ "$cleanup_converted" == "1" ]; then
    rm -rf "$OUTPUT_DIR"
    echo "   ✅ Converted map verwijderd"
fi

# Optie 2: Originele bestanden verwijderen
echo ""
echo "⚠️  Wil je de ORIGINELE bronbestanden verwijderen?"
echo "   📂 $(realpath "$INPUT_DIR")"
echo "   📊 ${#source_files[@]} bestanden"
echo "  1) Ja, verwijder originelen"
echo "  2) Nee, behouden (aanbevolen)"
echo ""
read -p "Keuze [1/2]: " cleanup_originals

if [ "$cleanup_originals" == "1" ]; then
    echo ""
    echo "🚨 WAARSCHUWING: Dit verwijdert alle originele MOD/AVI bestanden!"
    echo "   Locatie: $INPUT_DIR"
    echo "   Dit kan NIET ongedaan worden gemaakt!"
    echo ""
    read -p "Weet je het ZEKER? Type 'JA' om te bevestigen: " confirm
    
    if [ "$confirm" == "JA" ]; then
        for file in "${source_files[@]}"; do
            [[ "$file" =~ \.(mp4|MP4)$ ]] && continue
            rm -f "$file"
            # Verwijder ook bijbehorende MOI bestanden
            moi_file="${file%.*}.MOI"
            [ -f "$moi_file" ] && rm -f "$moi_file"
        done
        echo "   ✅ Originele bestanden verwijderd"
    else
        echo "   ❌ Geannuleerd - originelen behouden"
    fi
fi

echo ""
echo "✨ Alles klaar!"
echo "📂 Bestanden staan in: $FINAL_DIR"

# Opruimen: Verwijder temporaire XProtect conversie map
[ -n "$temp_convert_dir" ] && [ -d "$temp_convert_dir" ] && rm -rf "$temp_convert_dir"
