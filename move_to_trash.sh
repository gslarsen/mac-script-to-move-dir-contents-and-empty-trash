#!/bin/bash
# Prevent sleep while the script is running
/usr/bin/caffeinate -i -w $$ &

LOGFILE="/Users/gregorylarsen/move_to_trash.log"
STDERR_LOGFILE="/Users/gregorylarsen/move_to_trash.stderr"
TRASH_DIR="/Users/gregorylarsen/.Trash"
SOURCE_DIR="/Users/gregorylarsen/Downloads"

# Truncate log files to start fresh with each run
> "$LOGFILE"
> "$STDERR_LOGFILE"

# Function to show error dialog
show_error_dialog() {
    response=$(osascript -e "display dialog \"Error occurred while moving files! Open ${SOURCE_DIR} to check.\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" with title \"Move to Trash\" buttons {\"No, thanks\", \"Open Source Directory\"} default button \"Open Source Directory\"" \
        2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE"))

    # Check the user's response
    if [[ "$response" == "button returned:Open Source Directory" ]]; then
        error_message=$(open "$SOURCE_DIR" 2>&1)
        if [[ $? -ne 0 ]]; then
            osascript -e "display dialog \"Failed to open ${SOURCE_DIR}.\n\n$error_message\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh\" with title \"Move to Trash\" buttons {\"OK\"} default button \"OK\"" \
                2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")
        fi
    fi
}

# Function to ensure files and directories are moved successfully
move_items() {
    echo "Moving files from $SOURCE_DIR to $TRASH_DIR..." | tee -a "$LOGFILE"

    # Move files safely, handling spaces in filenames
    find "$SOURCE_DIR" -mindepth 1 -type f -print0 | xargs -0 -I {} mv -n "{}" "$TRASH_DIR" 2>>"$STDERR_LOGFILE"

    echo "Moving directories from $SOURCE_DIR to $TRASH_DIR..." | tee -a "$LOGFILE"

    # Move directories safely, handling spaces in folder names
    find "$SOURCE_DIR" -mindepth 1 -type d -depth -print0 | xargs -0 -I {} mv -n "{}" "$TRASH_DIR" 2>>"$STDERR_LOGFILE"

    # Retry logic with rsync in case of stubborn files
    if [[ -n "$(find "$SOURCE_DIR" -mindepth 1 2>/dev/null)" ]]; then
        echo "Warning: Some items could not be moved. Retrying..." | tee -a "$LOGFILE"

        rsync -a --remove-source-files "$SOURCE_DIR"/ "$TRASH_DIR"/ >> "$LOGFILE" 2>>"$STDERR_LOGFILE"

        # Remove empty directories after rsync
        find "$SOURCE_DIR" -type d -empty -delete 2>>"$STDERR_LOGFILE"

        # Final check for any remaining items
        remaining_items=$(find "$SOURCE_DIR" -mindepth 1 2>/dev/null)
        if [[ -n "$remaining_items" ]]; then
            echo "Error: Some items could not be moved even after retrying. Check manually." | tee -a "$LOGFILE"
            echo "$remaining_items" | tee -a "$LOGFILE"
        else
            echo "All remaining items successfully moved after retry." | tee -a "$LOGFILE"
        fi
    fi

    echo "Files and directories moved successfully." | tee -a "$LOGFILE"
}

# Main Script Logic
{
    echo "Script started at $(date)" | tee -a "$LOGFILE"

    # Ensure permission before moving
    chmod -R u+w "$SOURCE_DIR" 2>>"$STDERR_LOGFILE"

    move_items

    echo "Files moved successfully." | tee -a "$LOGFILE"

    # Try cleaning up Trash and handle errors
    echo "Cleaning up Trash..." | tee -a "$LOGFILE"
    echo "Items in Trash before cleanup:" >> "$LOGFILE"
    find "$TRASH_DIR" -mindepth 1 -print >> "$LOGFILE"

    find "$TRASH_DIR" -mindepth 1 -exec rm -rf "{}" + 2>>"$STDERR_LOGFILE"

    if [[ $? -ne 0 ]]; then
        echo "Error: Could not clean up Trash." | tee -a "$LOGFILE"
        show_error_dialog
        exit 1
    fi

    echo "Trash cleaned successfully." | tee -a "$LOGFILE"

    # Show success notification
    osascript -e 'display dialog "Download files moved to Trash and Trash emptied!\n\nTo stop these, comment out osascripts in ~/move_to_trash.sh" with title "Move to Trash" buttons {"OK"} default button "OK"' \
        2> >(grep -v 'IMKClient subclass' | grep -v 'IMKInputSession subclass' >> "$STDERR_LOGFILE")

} >>"$LOGFILE" 2>>"$STDERR_LOGFILE"
