#!/bin/bash
# Sync KeePass Database to Google Drive
# Uses rclone and cron

# Directories
local_dir="/home/drumman22/Documents/keepassdb"
gdrive_dir="gdrive:/Documents/Databases/KeePass"
gdrive_backup_dir="$gdrive_dir/Backups"

# Check if log file exists, if not create it
max_size=100000  # 100 KB
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="$script_dir/sync_kpdb.log"

# Rotate log file if it exceeds max size
if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE") -gt $MAXSIZE ]; then
    mv "$LOGFILE" "$LOGFILE.1"  # current becomes .1
fi
touch $log_file

# Log functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][$1] $2" >> $log_file
    
    # Used for debugging
    # echo "[$(date +'%Y-%m-%d %H:%M:%S')][$1] $2"
}

log_error() {
    log "ERROR" "$1"
}

log_status() {
    log "STATUS" "$1"
}

log_info() {
    log "INFO" "$1"
}

log_success() {
    log "SUCCESS" "$1"
}

check_dependencies() {
    if ! command -v rclone &> /dev/null; then
        log_error "rclone could not be found. Please install it to use this script."
        exit 1
    fi
}

check_directories() {
    if ! rclone lsd "$local_dir" &> /dev/null; then
        log_error "Local KeePass directory not found: $local_dir"
        exit 1
    elif ! rclone lsd "$gdrive_dir" &> /dev/null; then
        log_error "Google Drive KeePass directory not found: $gdrive_dir"
        exit 1
    elif ! rclone lsd "$gdrive_backup_dir" &> /dev/null; then
        log_error "Google Drive Backup directory not found: $gdrive_backup_dir"
        exit 1
    fi
}

# 3 Arguments: ($1: directory, $2: file_names_array, $3: file_timestamps_array)
_get_files_from_dir() {
    log_status "Fetching files from: $1"
    local lsl_full=$(rclone lsl "$1" --max-depth 1)
    local -n file_names_ref=$2
    local -n file_timestamps_ref=$3

    while IFS= read -r line; do
        # Extract the filename and timestamp
        local filename=$(echo "$line" | awk '{print $4}')
        local timestamp=$(echo "$line" | awk '{print $2 " " $3}')
        local timestamp_epoch=$(date -d "$timestamp" +%s)

        # Store the filename and timestamp in arrays
        file_names_ref+=("$filename")
        file_timestamps_ref+=("$timestamp_epoch")
    done <<< "$lsl_full"

    # Logging
    log_success "Files retrieved from: $1"
    log_info "File names: ${file_names_ref[*]}"
    log_info "File timestamp epochs: ${file_timestamps_ref[*]}"
}

# 1 Argument: local directory
get_local_kpdb_files() {
    local_file_names=()
    local_file_timestamps=()
    _get_files_from_dir "$1" local_file_names local_file_timestamps
}

# 1 Arguement: gdrive driectctory
get_gdrive_kpdb_files() {
    gdrive_file_names=()
    gdrive_file_timestamps=()
    _get_files_from_dir "$1" gdrive_file_names gdrive_file_timestamps
}

# Compare timestamps of two files
# 2 Arguments: ($1: file_timestamp1, $2: file_timestamp2)
# Return: (1: file1 is newer, 2: file1 is older, 3: same age, 0: file not found)
compare_timestamps() {
    if [[ "$1" -gt "$2" ]]; then
        return 1
    elif [[ "$1" -lt "$2" ]]; then
        return 2
    else
        return 3
    fi
}

sync_files() {
    get_local_kpdb_files "$local_dir"
    get_gdrive_kpdb_files "$gdrive_dir"

    # Get unique file names
    local all_filenames=("${local_file_names[@]}" "${gdrive_file_names[@]}")
    local unique_filenames=($(printf "%s\n" "${all_filenames[@]}" | sort -u))

    log_status "Starting file sync process..."
    for filename in "${unique_filenames[@]}"; do
        local local_idx=-1
        local gdrive_idx=-1

        # Find the index of the filename in local and gdrive arrays
        for i in "${!local_file_names[@]}"; do
            if [[ "${local_file_names[$i]}" == "$filename" ]]; then
                local_idx=$i
                break
            fi
        done
        for i in "${!gdrive_file_names[@]}"; do
            if [[ "${gdrive_file_names[$i]}" == "$filename" ]]; then
                gdrive_idx=$i
                break
            fi
        done

        # Check if file only exists in local
        if [[ $local_idx -ne -1 && $gdrive_idx -eq -1 ]]; then
            log_info "File $filename exists only locally. Uploading to Google Drive..."
            rclone copyto "$local_dir/$filename" "$gdrive_dir/$filename"
            log_success "Uploaded $filename to Google Drive."
        # Check if file only exists in gdrive
        elif [[ $local_idx -eq -1 && $gdrive_idx -ne -1 ]]; then
            log_info "File $filename exists only on Google Drive. Downloading to local..."
            rclone copyto "$gdrive_dir/$filename" "$local_dir/$filename"
            log_success "Downloaded '$filename' to local."
        else # File exists in both local and gdrive
            compare_timestamps "${local_file_timestamps[$local_idx]}" "${gdrive_file_timestamps[$gdrive_idx]}"
            local result=$?

            if [[ $result -eq 1 ]]; then
                log_info "File $filename is newer locally. Backing up and uploading..."
                rclone copyto "$gdrive_dir/$filename" "$gdrive_backup_dir/$(date +%Y-%m-%d_%H-%M-%S)-$filename"
                rclone copyto "$local_dir/$filename" "$gdrive_dir/$filename"
                log_success "Backup made and $filename uploaded."
            elif [[ $result -eq 2 ]]; then
                log_info "File $filename is newer on Google Drive. Downloading..."
                rclone copyto "$gdrive_dir/$filename" "$local_dir/$filename"
                log_success "Updated $filename."
            else
                log_info "File $filename is already synced."
            fi
        fi
    done
    log_success "File sync completed."
}

main() {
    log_status "Starting KeePass Sync Task..."
    check_dependencies
    check_directories
    sync_files
    log_status "Ending KeePass Sync Task."
}   
main