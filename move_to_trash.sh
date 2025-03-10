#!/bin/bash
# Prevent the Mac from sleeping while this script is running
/usr/bin/caffeinate -i -w $$ &

LOGFILE="$HOME/move_to_trash.log"
STDERR_LOGFILE="$HOME/move_to_trash.stderr"
TRASH_DIR="$HOME/.Trash"
MOBILE_TRASH="$HOME/Library/Mobile Documents/.Trash"
SOURCE_DIR="$HOME/Downloads"

# Clear out log files for a fresh run
> "$LOGFILE"
> "$STDERR_LOGFILE"

# show_error_dialog: Displays an AppleScript dialog if errors occur
show_error_dialog() {
    response=$(osascript -e "display dialog \"Error occurred while moving files! Open ${SOURCE_DIR} to check.\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
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

# Moves all files and directories from SOURCE_DIR to TRASH_DIR
# with retry logic using rsync if needed
move_items() {
    echo "Moving files from $SOURCE_DIR to $TRASH_DIR..." >> "$LOGFILE"

    # Move files safely, handling spaces in filenames
    find "$SOURCE_DIR" -mindepth 1 -type f -print0 | xargs -0 -I {} mv -n "{}" "$TRASH_DIR" 2>>"$STDERR_LOGFILE"

    echo "Moving directories from $SOURCE_DIR to $TRASH_DIR..." >> "$LOGFILE"

    # Move directories safely, handling spaces in folder names
    find "$SOURCE_DIR" -mindepth 1 -type d -depth -print0 | xargs -0 -I {} mv -n "{}" "$TRASH_DIR" 2>>"$STDERR_LOGFILE"

    # Short delay to let macOS (or iCloud) catch up
    echo "Waiting briefly before retry checks..." >> "$LOGFILE"
    sleep 5

    # Retry logic with rsync in case of stubborn files
    local remaining
    remaining=$(find "$SOURCE_DIR" -mindepth 1 2>/dev/null)
    if [[ -n "$remaining" ]]; then
        echo "Warning: Some items could not be moved. Retrying with rsync..." >> "$LOGFILE"

        rsync -a --remove-source-files "$SOURCE_DIR"/ "$TRASH_DIR"/ >> "$LOGFILE" 2>>"$STDERR_LOGFILE"

        # Remove empty directories after rsync
        find "$SOURCE_DIR" -type d -empty -delete 2>>"$STDERR_LOGFILE"

        # Final check for any remaining items
        local remaining_after_retry
        remaining_after_retry=$(find "$SOURCE_DIR" -mindepth 1 2>/dev/null)
        if [[ -n "$remaining_after_retry" ]]; then
            echo "Error: Some items could not be moved even after retrying. Check manually." >> "$LOGFILE"
            echo "$remaining_after_retry" >> "$LOGFILE"
        else
            echo "All remaining items successfully moved after retry." >> "$LOGFILE"
        fi
    fi

    echo "Files and directories moved successfully." >> "$LOGFILE"
}

# Removes all items from local & iCloud Trash with retry logic
cleanup_trash() {
    echo "Cleaning up Trash..." | tee -a "$LOGFILE"

    echo "Items in local Trash (before cleanup):" >> "$LOGFILE"
    find "$TRASH_DIR" -mindepth 1 -print | sed 's/^/\t/' >> "$LOGFILE"

    # check iCloud Trash as well:
    if [ -d "$MOBILE_TRASH" ]; then
      echo "Items in iCloud Trash (before cleanup):" >> "$LOGFILE"
      find "$MOBILE_TRASH" -mindepth 1 -print | sed 's/^/\t/' >> "$LOGFILE"
    fi

    # Attempt to remove all items from local .Trash
    find "$TRASH_DIR" -mindepth 1 -exec rm -rf "{}" + 2>>"$STDERR_LOGFILE"

    # Attempt to remove all items from iCloud .Trash (if it exists)
    if [ -d "$MOBILE_TRASH" ]; then
      find "$MOBILE_TRASH" -mindepth 1 -exec rm -rf "{}" + 2>>"$STDERR_LOGFILE"
    fi

    # Check exit code of the last find/rm
    if [[ $? -ne 0 ]]; then
        echo "Error: Could not clean up Trash." | tee -a "$LOGFILE"
        show_error_dialog
        exit 1
    fi

    # Optional: short wait & re-check if anything remains
    echo "Waiting briefly to ensure all trash items removed..." >> "$LOGFILE"
    sleep 5

    local leftover_trash leftover_icloud_trash
    leftover_trash=$(find "$TRASH_DIR" -mindepth 1 2>/dev/null)
    if [ -d "$MOBILE_TRASH" ]; then
      leftover_icloud_trash=$(find "$MOBILE_TRASH" -mindepth 1 2>/dev/null)
    fi

    if [[ -n "$leftover_trash" || -n "$leftover_icloud_trash" ]]; then
        echo "Some items still remain in Trash after cleanup:" >> "$LOGFILE"
        [ -n "$leftover_trash" ] && echo "$leftover_trash" >> "$LOGFILE"
        [ -n "$leftover_icloud_trash" ] && echo "$leftover_icloud_trash" >> "$LOGFILE"
    else
        echo "Trash cleaned successfully." | tee -a "$LOGFILE"
    fi
}

# Main
{
    echo "Script started at $(date)"

    # Ensure permission before moving
    chmod -R u+w "$SOURCE_DIR" 2>>"$STDERR_LOGFILE"

    # Move items from SOURCE_DIR to Trash (with retries)
    move_items

    # Cleanup the Trash (local + iCloud) thoroughly
    cleanup_trash

    # Show success notification
    osascript -e "display dialog \"Download files moved to Trash and Trash emptied!\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" \
      with title \"Move to Trash\" buttons {\"OK\"} default button \"OK\"" \
      2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")

} >>"$LOGFILE" 2>>"$STDERR_LOGFILE"
