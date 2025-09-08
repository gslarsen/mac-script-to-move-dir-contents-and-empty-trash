#!/bin/bash
# Prevent the Mac from sleeping while this script is running
/usr/bin/caffeinate -i -w $$ &

LOGFILE="$HOME/move_to_trash.log"
STDERR_LOGFILE="$HOME/move_to_trash.stderr"
TRASH_DIR="$HOME/.Trash"
MOBILE_TRASH="$HOME/Library/Mobile Documents/.Trash"
SOURCE_DIR="$HOME/Downloads"
MAX_RETRIES=3
RETRY_DELAY=10

# Clear out log files for a fresh run
> "$LOGFILE"
> "$STDERR_LOGFILE"

log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# show_error_dialog: Displays an AppleScript dialog if errors occur
show_error_dialog() {
    local message="$1"
    response=$(osascript -e "display dialog \"$message\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
        with title \"Move to Trash\" buttons {\"No, thanks\", \"Open Source Directory\"} default button \"Open Source Directory\"" \
        2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE"))

    if [[ "$response" == "button returned:Open Source Directory" ]]; then
        error_message=$(open "$SOURCE_DIR" 2>&1)
        if [[ $? -ne 0 ]]; then
            osascript -e "display dialog \"Failed to open ${SOURCE_DIR}.\n\n$error_message\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
                with title \"Move to Trash\" buttons {\"OK\"} default button \"OK\"" \
                2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")
        fi
    fi
}

# Verify if the directory is empty
verify_empty_dir() {
    local dir="$1"
    local remaining_count=$(find "$dir" -mindepth 1 | wc -l)
    remaining_count=$(echo "$remaining_count" | tr -d '[:space:]')

    if [[ "$remaining_count" -gt 0 ]]; then
        log_message "Directory $dir still contains $remaining_count items"
        return 1
    else
        log_message "Directory $dir is empty"
        return 0
    fi
}

# Moves all files and directories from SOURCE_DIR to TRASH_DIR
# with improved retry logic
move_items() {
    log_message "Moving files from $SOURCE_DIR to $TRASH_DIR..."

    # First count all items
    local total_items=$(find "$SOURCE_DIR" -mindepth 1 | wc -l)
    total_items=$(echo "$total_items" | tr -d '[:space:]')
    log_message "Found $total_items items to move from $SOURCE_DIR"

    # Ensure permissions before moving
    chmod -R u+w "$SOURCE_DIR" 2>>"$STDERR_LOGFILE"

    # Handle files first
    log_message "Moving files..."
    find "$SOURCE_DIR" -mindepth 1 -type f -print0 | xargs -0 -J {} mv -f {} "$TRASH_DIR/" 2>>"$STDERR_LOGFILE"

    # Then handle directories, starting from the deepest level
    log_message "Moving directories..."
    find "$SOURCE_DIR" -mindepth 1 -type d -depth -print0 | xargs -0 -J {} mv -f {} "$TRASH_DIR/" 2>>"$STDERR_LOGFILE"

    # Verify and retry if needed
    local retry_count=0
    while ! verify_empty_dir "$SOURCE_DIR" && [[ $retry_count -lt $MAX_RETRIES ]]; do
        retry_count=$((retry_count + 1))
        log_message "Retry $retry_count/$MAX_RETRIES: Some items could not be moved. Waiting $RETRY_DELAY seconds before retrying..."
        sleep $RETRY_DELAY

        # List problem files for debugging
        log_message "Problem items:"
        find "$SOURCE_DIR" -mindepth 1 -print | sed 's/^/\t/' >> "$LOGFILE"

        # Try with rsync for better handling of edge cases
        log_message "Attempting rsync method..."
        rsync -av --remove-source-files "$SOURCE_DIR"/ "$TRASH_DIR"/ >> "$LOGFILE" 2>>"$STDERR_LOGFILE"

        # Remove any empty directories after rsync
        find "$SOURCE_DIR" -type d -empty -delete 2>>"$STDERR_LOGFILE"

        # For special cases, try targeting specific file types
        log_message "Attempting targeted approach for remaining items..."
        find "$SOURCE_DIR" -mindepth 1 -type f -name ".*" -print0 | xargs -0 -J {} mv -f {} "$TRASH_DIR/" 2>>"$STDERR_LOGFILE"
        find "$SOURCE_DIR" -mindepth 1 -type f -name "._*" -print0 | xargs -0 -J {} mv -f {} "$TRASH_DIR/" 2>>"$STDERR_LOGFILE"
    done

    # Final check
    if verify_empty_dir "$SOURCE_DIR"; then
        log_message "All items successfully moved to Trash"
        return 0
    else
        log_message "ERROR: Could not move all items to Trash after $MAX_RETRIES retries"
        show_error_dialog "Error occurred while moving files! Some files couldn't be moved. Open ${SOURCE_DIR} to check."
        return 1
    fi
}

# Removes all items from local & iCloud Trash with improved retry logic
cleanup_trash() {
    log_message "Cleaning up Trash..."

    # Count items in Trash before cleanup
    local trash_count=$(find "$TRASH_DIR" -mindepth 1 | wc -l)
    trash_count=$(echo "$trash_count" | tr -d '[:space:]')
    log_message "Found $trash_count items in local Trash before cleanup"

    # Also check iCloud Trash
    local icloud_trash_count=0
    if [ -d "$MOBILE_TRASH" ]; then
        icloud_trash_count=$(find "$MOBILE_TRASH" -mindepth 1 | wc -l)
        icloud_trash_count=$(echo "$icloud_trash_count" | tr -d '[:space:]')
        log_message "Found $icloud_trash_count items in iCloud Trash before cleanup"
    fi

    # Attempt to empty local Trash using direct file removal
    log_message "Emptying local Trash..."
    local retry_count=0

    # First pass - handle normal files
    log_message "Removing normal files from Trash..."
    find "$TRASH_DIR" -mindepth 1 -type f -print0 | xargs -0 -J {} rm -f {} 2>>"$STDERR_LOGFILE"

    # Wait a moment
    sleep 2

    # Then directories - from deepest first
    log_message "Removing directories from Trash..."
    find "$TRASH_DIR" -mindepth 1 -type d -depth -print0 | xargs -0 -J {} rm -rf {} 2>>"$STDERR_LOGFILE"

    # Retry logic for stubborn files
    while ! verify_empty_dir "$TRASH_DIR" && [[ $retry_count -lt $MAX_RETRIES ]]; do
        retry_count=$((retry_count + 1))
        log_message "Retry $retry_count/$MAX_RETRIES: Some items remain in Trash. Waiting $RETRY_DELAY seconds before retrying..."
        sleep $RETRY_DELAY

        # List problem files for debugging
        log_message "Problem items in Trash:"
        find "$TRASH_DIR" -mindepth 1 -print | sed 's/^/\t/' >> "$LOGFILE"

        # Unlock any locked files and try again
        log_message "Attempting unlocking and removal for locked files..."
        find "$TRASH_DIR" -mindepth 1 -print0 | xargs -0 -J {} chflags -R nouchg {} 2>>"$STDERR_LOGFILE"
        find "$TRASH_DIR" -mindepth 1 -print0 | xargs -0 -J {} chflags -R noschg {} 2>>"$STDERR_LOGFILE"
        find "$TRASH_DIR" -mindepth 1 -print0 | xargs -0 -J {} chmod -R 777 {} 2>>"$STDERR_LOGFILE"

        # Try removing files again
        find "$TRASH_DIR" -mindepth 1 -type f -print0 | xargs -0 -J {} rm -f {} 2>>"$STDERR_LOGFILE"
        sleep 2
        find "$TRASH_DIR" -mindepth 1 -type d -depth -print0 | xargs -0 -J {} rm -rf {} 2>>"$STDERR_LOGFILE"
    done

    # Handle iCloud Trash if exists
    if [ -d "$MOBILE_TRASH" ]; then
        log_message "Emptying iCloud Trash..."
        retry_count=0

        # First pass for iCloud Trash
        find "$MOBILE_TRASH" -mindepth 1 -type f -print0 | xargs -0 -J {} rm -f {} 2>>"$STDERR_LOGFILE"
        sleep 2
        find "$MOBILE_TRASH" -mindepth 1 -type d -depth -print0 | xargs -0 -J {} rm -rf {} 2>>"$STDERR_LOGFILE"

        # Retry logic
        while ! verify_empty_dir "$MOBILE_TRASH" && [[ $retry_count -lt $MAX_RETRIES ]]; do
            retry_count=$((retry_count + 1))
            log_message "Retry $retry_count/$MAX_RETRIES: Some items remain in iCloud Trash. Waiting $RETRY_DELAY seconds before retrying..."
            sleep $RETRY_DELAY

            # List problem files for debugging
            log_message "Problem items in iCloud Trash:"
            find "$MOBILE_TRASH" -mindepth 1 -print | sed 's/^/\t/' >> "$LOGFILE"

            # Unlock and try again
            find "$MOBILE_TRASH" -mindepth 1 -print0 | xargs -0 -J {} chflags -R nouchg {} 2>>"$STDERR_LOGFILE"
            find "$MOBILE_TRASH" -mindepth 1 -print0 | xargs -0 -J {} chflags -R noschg {} 2>>"$STDERR_LOGFILE"
            find "$MOBILE_TRASH" -mindepth 1 -print0 | xargs -0 -J {} chmod -R 777 {} 2>>"$STDERR_LOGFILE"

            # Try removing files again
            find "$MOBILE_TRASH" -mindepth 1 -type f -print0 | xargs -0 -J {} rm -f {} 2>>"$STDERR_LOGFILE"
            sleep 2
            find "$MOBILE_TRASH" -mindepth 1 -type d -depth -print0 | xargs -0 -J {} rm -rf {} 2>>"$STDERR_LOGFILE"
        done
    fi

    # Final verification
    local local_trash_empty=0
    local icloud_trash_empty=0

    verify_empty_dir "$TRASH_DIR" && local_trash_empty=1

    if [ -d "$MOBILE_TRASH" ]; then
        verify_empty_dir "$MOBILE_TRASH" && icloud_trash_empty=1
    else
        icloud_trash_empty=1  # If no iCloud Trash, consider it empty
    fi

    if [[ $local_trash_empty -eq 1 && $icloud_trash_empty -eq 1 ]]; then
        log_message "All Trash items successfully removed"
        return 0
    else
        log_message "WARNING: Could not remove all items from Trash"
        if [[ $local_trash_empty -eq 0 ]]; then
            log_message "Local Trash still contains items"
        fi
        if [[ $icloud_trash_empty -eq 0 ]]; then
            log_message "iCloud Trash still contains items"
        fi
        return 1
    fi
}

# Main
{
    log_message "Script started"

    # Move items from SOURCE_DIR to Trash
    move_items
    move_result=$?

    # Cleanup the Trash
    cleanup_trash
    trash_result=$?

    # Show appropriate notification based on results - keeping original osascript calls
    if [[ $move_result -eq 0 && $trash_result -eq 0 ]]; then
        osascript -e "display dialog \"Download files moved to Trash and Trash emptied!\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
          with title \"Move to Trash\" buttons {\"OK\"} default button \"OK\"" \
          2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")
    elif [[ $move_result -eq 0 && $trash_result -ne 0 ]]; then
        osascript -e "display dialog \"Download files moved to Trash but some Trash items could not be emptied.\n\nSee log file for details.\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
          with title \"Move to Trash - Warning\" buttons {\"OK\"} default button \"OK\"" \
          2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")
    elif [[ $move_result -ne 0 ]]; then
        show_error_dialog "Error occurred while moving files! Some files in ${SOURCE_DIR} may not have been moved to Trash. See log file for details."
    fi

    log_message "Script finished"
} 2>>"$STDERR_LOGFILE"
