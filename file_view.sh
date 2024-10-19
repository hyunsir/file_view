#!/bin/bash

# Initialize UI, display current directory and prompt message
function init_ui {
    tput clear  # Clear the screen
    echo "Current directory: $(pwd)"
    echo "Use the arrow keys to navigate, right arrow to enter folder, left arrow to go back, press q to quit."
    # Dynamically generate separator, matching the width of the terminal
    local total_width=$(tput cols)
    printf '=%.0s' $(eval "echo {1..$total_width}")
    echo ""
}

# Convert byte size to human-readable format (KB, MB, etc.)
function human_readable_size {
    size=$1
    if command -v numfmt > /dev/null; then
        # Use numfmt for conversion, adding a space between number and unit
        numfmt --to=iec --suffix=" B" --format="%.1f" "$size"
    else
        # Manually convert to readable format, adding a space
        if [ "$size" -lt 1024 ]; then
            echo "${size} B"
        elif [ "$size" -lt 1048576 ]; then
            echo "$((size / 1024)) KB"
        elif [ "$size" -lt 1073741824 ]; then
            echo "$((size / 1048576)) MB"
        else
            echo "$((size / 1073741824)) GB"
        fi
    fi
}

# List all files and directories in the current directory, and categorize them
function list_items {
    items=()
    items_details=()

    # Get directories first
    for file in $(ls -1a); do
        if [ -d "$file" ]; then
            items+=("$file")
            items_details+=("")  # Directories do not need to show size
        fi
    done

    # Get files next
    for file in $(ls -1a); do
        if [ ! -d "$file" ]; then
            items+=("$file")
            # Get file size
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
            if [ -n "$size" ]; then
                # Convert to readable format with space
                human_readable_size=$(human_readable_size "$size")
                items_details+=("$human_readable_size")
            else
                items_details+=("")  # Show empty if unable to get size
            fi
        fi
    done
}

# Get the size of the current terminal window
function get_terminal_size {
    rows=$(tput lines)  # Get terminal rows
    cols=$(tput cols)  # Get terminal columns
    display_lines=$((rows - 5))  # Calculate number of displayable lines, reserving top area
    left_width=$((cols / 2))  # Left side width is half the terminal
    right_width=$((cols - left_width - 2))  # Right side width, subtracting separator
}

# Display the list of files and directories, with scrolling if necessary
function display_items {
    local current=$1
    local offset=$2
    local total=${#items[@]}

    # Set file name width to ensure alignment
    local name_width=$((left_width - 12))  # Leave space for file size
    local size_width=10

    for ((i = 0; i < display_lines && (i + offset) < total; i++)); do
        file="${items[$((i + offset))]}"
        file_detail="${items_details[$((i + offset))]}"

        if [ -d "$file" ]; then
            # Display directories in blue
            if [ $((i + offset)) -eq $current ]; then
                printf "\e[1;34m> %-*s\e[0m\n" "$name_width" "$file/"  # Highlight selected directory, left aligned
            else
                printf "  \e[1;34m%-*s\e[0m\n" "$name_width" "$file/"  # Regular directory, left aligned
            fi
        elif [ -x "$file" ]; then
            # Display executable files in green
            if [ $((i + offset)) -eq $current ]; then
                printf "\e[1;32m> %-*s %*s\e[0m\n" "$name_width" "$file" "$size_width" ""  # Highlight selected executable, left aligned, right empty
            else
                printf "  \e[1;32m%-*s %*s\e[0m\n" "$name_width" "$file" "$size_width" ""  # Regular executable, left aligned, right empty
            fi
        else
            # Display regular files with size
            if [ $((i + offset)) -eq $current ]; then
                printf "> %-*s %*s\n" "$name_width" "$file" "$size_width" "$file_detail"  # Highlight selected file, left aligned, right with size
            else
                printf "  %-*s %*s\n" "$name_width" "$file" "$size_width" "$file_detail"  # Regular file, left aligned, right with size
            fi
        fi
    done
}

# Preview the first few lines of the selected file
function display_file_preview {
    local file=$1
    local max_lines_to_display=$((rows - 7))  # Maximum lines to display based on terminal size
    local lines_to_display=$((max_lines_to_display))

    if [ -f "$file" ]; then
        # Use head to read the first few lines, and check for binary characters with perl
        if head -n "$lines_to_display" "$file" | perl -ne 'if (/[\x00-\x08\x0B\x0C\x0E-\x1F]/) { exit 1 }'; then
            # Move cursor to right display area
            tput cup 2 $((left_width + 2))
            printf "\e[1;37m%-*s\e[0m\n" "$right_width" "File preview: $file"

            # Dynamically generate separator, matching right side width
            tput cup 3 $((left_width + 2))
            printf "%0.s-" $(seq 1 $right_width)
            echo ""

            # Use head to get the first few lines of the file
            head -n "$lines_to_display" "$file" | while IFS= read -r line; do
                # Truncate the line if it exceeds the right side width, adding "..." at the end
                if [ "${#line}" -gt "$right_width" ]; then
                    line="${line:0:right_width-3}..."  # Truncate and add "..." symbol
                fi
                # Move cursor to right display area
                tput cup $((4 + count)) $((left_width + 2))
                printf "%-${right_width}s\n" "$line"
                ((count++))
            done

            # Dynamically generate end separator
            tput cup $((3 + lines_to_display + 1)) $((left_width + 2))
            printf "%0.s-" $(seq 1 $right_width)
            echo ""
        else
            # Display a short message for binary files
            tput cup 2 $((left_width + 2))
            printf "\e[1;37m%-*s\e[0m\n" "$right_width" "File preview: $file (Binary file, preview not supported)"
        fi
    fi
}

# Main loop
function main {
    local current_selection=0   # Index of currently selected file or directory
    local scroll_offset=0  # Control scroll offset
    list_items
    get_terminal_size
    init_ui

    while true; do
        get_terminal_size  # Recalculate terminal size on each iteration
        # Refresh the screen and redisplay content
        tput clear
        init_ui

        # Display the list of files on the left
        display_items $current_selection $scroll_offset  # Display files and directories
        # Display file preview on the right (if a file)
        display_file_preview "${items[$current_selection]}"

        # Wait for user input
        read -rsn1 key
        case "$key" in
            $'\x1b')  # Handle arrow keys
                read -rsn2 key
                case "$key" in
                    "[A")  # Up arrow
                        ((current_selection--))
                        if [ $current_selection -lt 0 ]; then
                            current_selection=$((${#items[@]} - 1))  # Jump to the last file
                            scroll_offset=$((${#items[@]} - display_lines))  # Scroll to the bottom
                            if [ $scroll_offset -lt 0 ]; then
                                scroll_offset=0  # Prevent scrolling beyond available files
                            fi
                        elif [ $current_selection -lt $scroll_offset ]; then
                            ((scroll_offset--))  # Scroll up
                        fi
                        ;;
                    "[B")  # Down arrow
                        ((current_selection++))
                        if [ $current_selection -ge ${#items[@]} ]; then
                            current_selection=0  # Jump to the first file
                            scroll_offset=0  # Scroll to the top
                        elif [ $current_selection -ge $((scroll_offset + display_lines)) ]; then
                            ((scroll_offset++))  # Scroll down
                        fi
                        ;;
                    "[C")  # Right arrow: Enter directory if on a folder
                        if [ -d "${items[$current_selection]}" ]; then
                            cd "${items[$current_selection]}"
                            list_items
                            current_selection=0
                            scroll_offset=0
                            init_ui
                        fi
                        ;;
                    "[D")  # Left arrow: Go back to the previous folder
                        cd ..
                        list_items
                        current_selection=0
                        scroll_offset=0
                        init_ui
                        ;;
                esac
                ;;
            "")  # Enter key: Enter directory or preview file
                if [ -d "${items[$current_selection]}" ]; then
                    cd "${items[$current_selection]}"
                    list_items  # Refresh the file list
                    current_selection=0
                    scroll_offset=0  # Reset scroll offset
                    get_terminal_size  # Recalculate terminal size
                    init_ui
                elif [ -f "${items[$current_selection]}" ]; then
                    # Preview the file if selected
                    display_file_preview "${items[$current_selection]}"
                fi
                ;;
            q)  # Press 'q' to quit and return to the current directory
                tput clear
                echo "$(pwd)"
                exit 0
                ;;
        esac
    done
}

# Run the main program
main
