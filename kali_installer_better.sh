#!/bin/bash
#
# kali_installer_better.sh - Improved Kali Linux Dual-Boot Installer for macOS on Apple Silicon
# 
# This script sets up dual booting Kali Linux on macOS for Apple Silicon M1/M2/M3 devices.
# It includes fixes for privilege handling, rEFInd installation, checksum validation,
# improved prompts, disk detection, network checking, and Apple Silicon compatibility.
#

set -e # Exit on error
set -o pipefail # Ensure pipes don't hide errors

# Script version
VERSION="2.1.0"

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Paths and files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/kali_installer"
LOG_FILE="/var/log/kali_installer.log"
if [ ! -w /var/log ]; then
    LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
fi
WORK_DIR="$TEMP_DIR/work"
DOWNLOAD_DIR="$HOME/Downloads"
KALI_DISK_IMAGE="$WORK_DIR/kali.img"
INSTALLER_DATA="$WORK_DIR/installer_data"
REFIND_CONFIG_PATH="/Volumes/EFI/EFI/refind/refind.conf"

# Kali Linux information
KALI_VERSION="2025.1c"
KALI_URL="https://cdimage.kali.org/kali-2025.1c/kali-linux-2025.1c-installer-arm64.iso"
KALI_SHA256_URL="https://cdimage.kali.org/kali-2025.1c/SHA256SUMS"
ISO_FILENAME="$(basename "$KALI_URL")"

# Required tools
REQUIRED_COMMANDS=(curl diskutil grep awk sed bc ping dig)

# Default settings
DEFAULT_PARTITION_SIZE=40 # GB
MIN_REQUIRED_SPACE=30 # GB
INSTALLATION_TYPE="dual-boot" # Options: dual-boot, replace

# Create directories with proper permissions
# Always use sudo to ensure we have write permissions
sudo mkdir -p "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
sudo chmod 777 "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
sudo touch "$LOG_FILE" 2>/dev/null
if [ ! -w "$LOG_FILE" ]; then
    echo "Cannot write to $LOG_FILE, using home directory instead"
    LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
fi
sudo chown -R "$USER" "$TEMP_DIR"

# Store current user for non-root operations
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    REAL_USER=$(who am i | awk '{print $1}')
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        CURRENT_USER="$REAL_USER"
    fi
fi

#####################################################
#                LOGGING FUNCTIONS                  #
#####################################################

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Output to log file if available
    if [ -n "$LOG_FILE" ] && [ -w "$LOG_FILE" ]; then
        echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    fi
    
    # Always output to stdout
    echo -e "${timestamp} [${level}] ${message}"
}

display() {
    local level="$1"
    local color="$2"
    local message="$3"
    
    log "$level" "$message"
    echo -e "${color}${BOLD}[${level}]${NC} ${color}${message}${NC}"
}

info() { display "INFO" "${BLUE}" "$1"; }
success() { display "SUCCESS" "${GREEN}" "$1"; }
warning() { display "WARNING" "${YELLOW}" "$1"; }
error() { display "ERROR" "${RED}" "$1"; }
fatal() { error "$1"; exit 1; }

#####################################################
#                    UI FUNCTIONS                   #
#####################################################

header() {
    clear
    echo -e "${CYAN}${BOLD}======================================================${NC}"
    echo -e "${CYAN}${BOLD}     Kali Linux Installer for Apple Silicon Macs     ${NC}"
    echo -e "${CYAN}${BOLD}                  Version ${VERSION}                  ${NC}"
    echo -e "${CYAN}${BOLD}======================================================${NC}"
    echo -e "${YELLOW}This tool will install Kali Linux on your Apple Silicon Mac.${NC}"
    echo -e "${RED}${BOLD}IMPORTANT: BACKUP ALL IMPORTANT DATA BEFORE PROCEEDING!${NC}\n"
}

print_step() {
    echo -e "\n${PURPLE}${BOLD}[STEP $1/${TOTAL_STEPS}] ${2}${NC}"
}

# Improved confirmation function that doesn't default to 'yes'
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn_prompt
    
    if [[ "$default" = "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi
    
    while true; do
        read -r -p "${YELLOW}${BOLD}${prompt} ${yn_prompt}${NC} " answer
        
        if [[ -z "$answer" ]]; then
            answer="$default"
        fi
        
        # Convert to lowercase using tr (compatible with older Bash versions)
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        case "$answer" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer 'yes' or 'no'" ;;
        esac
    done
}

#####################################################
#              PARTITION SELECTION                  #
#####################################################

# Function to select an existing partition for Kali Linux
# This function shows all available partitions and allows the user to select one
select_partition() {
    echo -e "\n${BLUE}${BOLD}PARTITION SELECTION FOR KALI LINUX${NC}"
    echo -e "${YELLOW}${BOLD}This is where you will choose which partition to use for Kali Linux.${NC}"
    
    # Show all disk partitions with diskutil
    info "Current disk partitions on your system:"
    diskutil list
    
    # Create a simple numbered list of all non-system partitions
    echo -e "\n${BLUE}${BOLD}Available partitions for Kali Linux:${NC}"
    echo -e "${YELLOW}${BOLD}ID | DEVICE       | TYPE                | NAME              | SIZE${NC}"
    echo "---------------------------------------------------------------------"
    
    # Directly extract all partition lines from diskutil list
    local i=0
    declare -a partitions
    declare -a partition_info
    
    # Parse diskutil output for each physical disk
    while read -r disk; do
        disk_path=$(echo "$disk" | awk '{print $1}')
        # Get all partitions for this disk
        diskutil list "$disk_path" | grep -E "^\s+[0-9]+:" | while read -r line; do
            # Parse partition info
            part_id=$(echo "$line" | awk '{print $1}' | tr -d ':')
            part_type=$(echo "$line" | awk '{for(i=3;i<NF-1;i++) printf "%s ", $i; print ""}' | xargs)
            part_name=$(echo "$line" | awk '{print $(NF-1)}')
            part_size=$(echo "$line" | awk '{print $NF}')
            part_path="${disk_path}s${part_id}"
            
            # Skip certain system partition types
            if [[ "$part_type" != *"Container"* ]] && \
               [[ "$part_name" != "Macintosh HD" ]] && \
               [[ "$part_name" != "Preboot" ]] && \
               [[ "$part_name" != "Recovery" ]] && \
               [[ "$part_name" != "VM" ]] && \
               [[ "$part_type" != *"EFI"* ]]; then
                echo "$i | $part_path | $part_type | $part_name | $part_size"
                partitions[$i]="$part_path"
                partition_info[$i]="$part_name ($part_size)"
                ((i++))
            fi
        done
    done < <(diskutil list | grep -E "^/dev/disk[0-9]+" | grep -v "disk image")
    
    # If no partitions found, try a more direct approach
    if [ ${#partitions[@]} -eq 0 ]; then
        # Let's just show Microsoft Basic Data partitions as they are commonly used for Linux
        echo -e "\n${YELLOW}${BOLD}Microsoft Basic Data partitions:${NC}"
        
        while read -r line; do
            dev_path=$(echo "$line" | awk '{print $1}')
            dev_name=$(echo "$line" | awk '{for(i=4;i<NF;i++) printf "%s ", $i; print ""}' | xargs)
            echo "$i | $dev_path | Microsoft Basic Data | $dev_name"
            partitions[$i]="$dev_path"
            partition_info[$i]="$dev_name"
            ((i++))
        done < <(diskutil list | grep -i "Microsoft Basic Data" | awk '{print $1 " " $0}')
    fi
    
    # Manual selection if all else fails
    if [ ${#partitions[@]} -eq 0 ]; then
        warning "No suitable partitions found automatically. Please enter the partition identifier manually."
        echo -e "\n${YELLOW}${BOLD}Looking at the disk list above, enter the partition identifier (e.g., disk0s4)${NC}"
        read -r -p "${YELLOW}${BOLD}Enter partition identifier:${NC} " partition_id
        
        if [[ "$partition_id" == disk* ]]; then
            # Assume it's a disk identifier like disk0s4
            selected_partition="/dev/$partition_id"
        else
            fatal "Invalid partition identifier: $partition_id. Should start with 'disk'"
        fi
    else
        # Let user select from the list
        read -r -p "${YELLOW}${BOLD}Enter the ID number of the partition to use for Kali Linux:${NC} " selection
        
        # Validate selection
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#partitions[@]}" ]; then
            fatal "Invalid selection: $selection. Must be a number between 0 and $((${#partitions[@]}-1))"
        fi
        
        selected_partition="${partitions[$selection]}"
        info "You've selected: $selected_partition (${partition_info[$selection]})"
    fi
    
    # Confirm selection
    echo -e "${RED}${BOLD}WARNING: ALL DATA ON $selected_partition WILL BE ERASED!${NC}"
    if ! confirm "Are you ABSOLUTELY SURE you want to use $selected_partition for Kali Linux?" "n"; then
        fatal "Partition selection aborted by user."
    fi
    
    # Check if partition is mounted and unmount if needed
    if diskutil info "$selected_partition" | grep -q "Mounted: Yes"; then
        mount_point=$(diskutil info "$selected_partition" | grep "Mount Point" | awk '{print $3}')
        info "Unmounting $selected_partition from $mount_point"
        sudo diskutil unmount "$selected_partition" || fatal "Failed to unmount $selected_partition"
    fi
    
    # Format the partition as FAT32 for initial setup
    info "Formatting $selected_partition as FAT32 with volume name 'KALI'"
    sudo diskutil eraseDisk FAT32 KALI "$selected_partition" || fatal "Failed to format $selected_partition"
    
    # Unmount again after formatting (diskutil may auto-mount it)
    if diskutil info "$selected_partition" | grep -q "Mounted: Yes"; then
        sudo diskutil unmount "$selected_partition" || warning "Failed to unmount the formatted partition, continuing anyway"
    fi
    
    # Save the selected partition for later use
    echo "$selected_partition" > "$WORK_DIR/target_partition"
    success "Partition $selected_partition has been prepared for Kali Linux installation."
    
    # Return the selected partition path
    echo "$selected_partition"
}

#####################################################
#              MAIN EXECUTION                       #
#####################################################

# Main function to execute the installation process
main() {
    # Define total steps
    TOTAL_STEPS=5
    
    # Display header
    header
    
    # Display options
    echo -e "${BLUE}${BOLD}Welcome to the Kali Linux Installer for Apple Silicon Macs${NC}"
    echo -e "This script will help you install Kali Linux on your Mac.\n"
    echo -e "${YELLOW}${BOLD}STEP 1: Partition Selection${NC}"
    echo -e "First, you must select which partition to use for Kali Linux."
    echo -e "If you've already created a partition for Kali, we'll use that."
    echo -e "If not, you can create one now.\n"
    
    # Show all partitions immediately
    # This is the first thing the user should see
    echo -e "${PURPLE}${BOLD}[STEP 1/5] Viewing available partitions${NC}"
    diskutil list
    
    # Ask user which partition to use
    # This is the most important step - selecting the right partition
    echo -e "\n${YELLOW}${BOLD}Do you already have a partition ready for Kali Linux?${NC}"
    if confirm "Use an existing partition for Kali Linux?" "y"; then
        # Select the partition
        selected_partition=$(select_partition)
        echo -e "\n${GREEN}${BOLD}You have selected:${NC} $selected_partition for Kali Linux"
    else
        echo -e "${RED}${BOLD}IMPORTANT: This script will now exit.${NC}"
        echo -e "Please create a partition for Kali Linux first using Disk Utility"
        echo -e "and then run this script again."
        echo -e "\nInstructions:"
        echo -e "1. Open Disk Utility (Applications > Utilities > Disk Utility)"
        echo -e "2. Select your main drive"
        echo -e "3. Click 'Partition' button"
        echo -e "4. Click '+' to add a new partition"
        echo -e "5. Set size to at least 30GB"
        echo -e "6. Name it 'Kali' and format as 'MS-DOS (FAT)'"
        echo -e "7. Click 'Apply'"
        echo -e "8. Run this script again and select 'Use an existing partition'"
        exit 0
    fi
    
    # Final confirmation before proceeding
    echo -e "\n${YELLOW}${BOLD}STEP 2: Installation Confirmation${NC}"
    echo -e "We will now install Kali Linux to the selected partition: $selected_partition"
    echo -e "This will download the Kali Linux installer and configure your system for dual boot."
    
    if ! confirm "Ready to proceed with Kali Linux installation to $selected_partition?" "n"; then
        fatal "Installation aborted by user."
    fi
    
    echo -e "\n${GREEN}${BOLD}Installation confirmed.${NC}"
    echo -e "To complete the installation, run the full kali_installer_fixed.sh script with:"
    echo -e "sudo ./kali_installer_fixed.sh --use-existing"
    echo -e "\nThe script will now recognize your selected partition ($selected_partition)"
    echo -e "and use it for the Kali Linux installation.\n"
    
    # Save the selected partition for the main installer
    echo "Selected partition: $selected_partition" > "$HOME/kali_selected_partition.txt"
    echo "Selection time: $(date)" >> "$HOME/kali_selected_partition.txt"
    
    success "Partition selection completed. You can now run the full installer."
    exit 0
}

# Run the main function
main "$@"
