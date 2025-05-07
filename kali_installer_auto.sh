#!/bin/bash
#
# kali_installer_auto.sh - Fully Automated Kali Linux Installer for macOS on Apple Silicon
# 
# This script automatically sets up dual booting Kali Linux on macOS M3 and M3 Pro devices.
# Similar to Asahi Linux installer, it handles the complete installation process.
#

set -e # Exit on error
set -o pipefail # Ensure pipes don't hide errors

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script version
VERSION="1.0.0"

# Paths and files
TEMP_DIR="/tmp/kali_installer"
LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
WORK_DIR="$TEMP_DIR/work"
DOWNLOAD_DIR="$HOME/Downloads"
KALI_DISK_IMAGE="$WORK_DIR/kali.img"
INSTALLER_DATA="$WORK_DIR/installer_data"

# Kali Linux information
KALI_VERSION="2025.1c"
KALI_URL="https://cdimage.kali.org/kali-2025.1c/kali-linux-2025.1c-installer-arm64.iso"
KALI_SHA256_URL="https://cdimage.kali.org/kali-2025.1c/SHA256SUMS"

# Required tools
REQUIRED_COMMANDS=(curl diskutil grep awk sed bc)

# Default settings
DEFAULT_PARTITION_SIZE=40 # GB
MIN_REQUIRED_SPACE=30 # GB
INSTALLATION_TYPE="dual-boot" # Options: dual-boot, replace

# Create directories
mkdir -p "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
touch "$LOG_FILE"

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
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

# UI functions
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

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$default" = "y" ]]; then
        local yn_prompt="[Y/n]"
    else
        local yn_prompt="[y/N]"
    fi
    
    read -p "${YELLOW}${BOLD}${prompt} ${yn_prompt}${NC} " answer
    
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    
    if [[ "$(echo $answer | tr '[:upper:]' '[:lower:]')" =~ ^(yes|y)$ ]]; then
        return 0
    else
        return 1
    fi
}

select_option() {
    local options=("$@")
    local selected=0
    local key=""

    # Hide cursor
    tput civis

    # Display options with highlighting
    function _display_options {
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}${BOLD}> ${options[$i]}${NC}"
            else
                echo -e "  ${options[$i]}"
            fi
        done
    }

    # Clear previous output and show new selection
    function _refresh_display {
        # Move cursor back up
        for ((i=0; i<${#options[@]}; i++)); do
            tput cuu1
        done
        _display_options
    }

    # Initial display
    _display_options

    # Handle key input
    while true; do
        read -s -n 1 key
        case "$key" in
            A|k) # Up arrow or k
                if [[ $selected -gt 0 ]]; then
                    ((selected--))
                    _refresh_display
                fi
                ;;
            B|j) # Down arrow or j
                if [[ $selected -lt $((${#options[@]}-1)) ]]; then
                    ((selected++))
                    _refresh_display
                fi
                ;;
            "") # Enter
                tput cnorm # Show cursor
                echo # New line
                return $selected
                ;;
        esac
    done
}

# Prerequisite check functions
check_sudo() {
    info "Checking for administrative privileges..."
    if [[ $EUID -ne 0 ]]; then
        warning "This script requires administrative privileges."
        echo "Please run it again with sudo:"
        echo "sudo $0 $*"
        exit 1
    fi
    success "Administrative privileges confirmed."
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check for required commands
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            fatal "Required command '$cmd' not found. Please install it and try again."
        fi
    done
    
    # Check macOS version
    os_version=$(sw_vers -productVersion)
    info "Detected macOS version: $os_version"
    
    # Ensure macOS Ventura (13) or higher
    if [[ $(echo "$os_version" | cut -d. -f1) -lt 13 ]]; then
        fatal "This script requires macOS Ventura (13.0) or higher. Current version: $os_version"
    fi
    
    # Check for Apple Silicon
    chip=$(sysctl -n machdep.cpu.brand_string)
    info "Detected CPU: $chip"
    
    if [[ "$chip" != *"Apple"* ]]; then
        fatal "This script is designed for Apple Silicon Macs (M1/M2/M3 series). Detected: $chip"
    fi
    
    # Check available disk space
    available_space=$(df -h / | awk 'NR==2 {print $4}' | sed 's/Gi//')
    info "Available disk space: ${available_space}GB"
    
    if (( $(echo "$available_space < $MIN_REQUIRED_SPACE" | bc -l) )); then
        warning "You have less than ${MIN_REQUIRED_SPACE}GB of free space. Kali Linux installation requires at least ${MIN_REQUIRED_SPACE}GB."
        if ! confirm "Do you want to continue anyway?"; then
            fatal "Installation aborted due to insufficient disk space."
        fi
    fi
    
    # Check if SIP is enabled
    sip_status=$(csrutil status | grep -o "enabled\|disabled")
    info "System Integrity Protection (SIP) is: $sip_status"
    
    if [[ "$sip_status" == "enabled" ]]; then
        warning "System Integrity Protection (SIP) is enabled. This may cause issues with dual booting."
        echo -e "${YELLOW}To disable SIP, you need to:${NC}"
        echo "1. Restart your Mac and hold down Command (⌘) + R to enter Recovery Mode"
        echo "2. Click Utilities > Terminal"
        echo "3. Type: csrutil disable"
        echo "4. Restart your Mac"
        
        if ! confirm "Do you want to continue with SIP enabled?"; then
            fatal "Installation aborted. Please disable SIP and run the script again."
        fi
    fi
    
    success "Prerequisites check completed."
}

# Installation steps
download_kali() {
    print_step "1" "Downloading Kali Linux"
    
    mkdir -p "$DOWNLOAD_DIR"
    KALI_ISO="$DOWNLOAD_DIR/kali-linux-$KALI_VERSION-installer-arm64.iso"
    
    # Check if ISO already exists
    if [[ -f "$KALI_ISO" ]]; then
        info "Kali Linux ISO already exists at $KALI_ISO"
        if confirm "Do you want to download it again?" "n"; then
            rm "$KALI_ISO"
        else
            info "Using existing ISO file."
            SKIP_DOWNLOAD=true
        fi
    fi
    
    # Download the ISO if needed
    if [[ "$SKIP_DOWNLOAD" != true ]]; then
        info "Downloading Kali Linux ISO from $KALI_URL..."
        info "This may take a while depending on your internet connection."
        
        curl -# -L "$KALI_URL" -o "$KALI_ISO" || fatal "Failed to download Kali Linux ISO"
        success "Download completed."
    fi
    
    # Download SHA256SUMS file
    info "Downloading SHA256SUMS file to verify the ISO..."
    curl -L "$KALI_SHA256_URL" -o "$DOWNLOAD_DIR/SHA256SUMS" || fatal "Failed to download SHA256SUMS file"
    
    # Verify the ISO checksum
    info "Verifying ISO checksum..."
    expected_sha256=$(grep "$(basename "$KALI_ISO")" "$DOWNLOAD_DIR/SHA256SUMS" | awk '{print $1}')
    
    if [[ -z "$expected_sha256" ]]; then
        warning "Could not find the expected SHA256 hash for $(basename "$KALI_ISO") in the SHA256SUMS file."
        warning "This could mean the ISO name has changed or the SHA256SUMS file format has changed."
        if ! confirm "Do you want to continue without verification?"; then
            fatal "Installation aborted due to verification failure."
        fi
    else
        actual_sha256=$(shasum -a 256 "$KALI_ISO" | awk '{print $1}')
        
        if [[ "$actual_sha256" == "$expected_sha256" ]]; then
            success "ISO verification successful. Checksum matches."
        else
            error "ISO verification failed. Checksums do not match."
            error "Expected: $expected_sha256"
            error "Actual:   $actual_sha256"
            if ! confirm "Do you want to continue with a potentially corrupted ISO?"; then
                fatal "Installation aborted due to checksum mismatch."
            fi
        fi
    fi
    
    cp "$KALI_ISO" "$KALI_DISK_IMAGE"
    success "Kali Linux ISO prepared for installation."
}

install_bootloader() {
    print_step "2" "Installing and configuring bootloader"
    
    info "Installing rEFInd bootloader..."
    
    # Install Homebrew if not already installed
    if ! command -v brew &>/dev/null; then
        info "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fatal "Failed to install Homebrew"
        success "Homebrew installed successfully."
    else
        info "Homebrew is already installed."
    fi
    
    # Install rEFInd via Homebrew
    brew install refind || fatal "Failed to install rEFInd"
    
    # Mount EFI partition
    info "Mounting EFI partition..."
    EFI_DEVICE=$(diskutil list | grep EFI | awk '{print $NF}')
    
    if [[ -z "$EFI_DEVICE" ]]; then
        fatal "Could not find EFI partition."
    fi
    
    # Create mount point if it doesn't exist
    mkdir -p /Volumes/EFI
    
    # Unmount if already mounted
    if mount | grep "/Volumes/EFI" &>/dev/null; then
        info "EFI partition is already mounted. Unmounting..."
        diskutil unmount /Volumes/EFI || fatal "Failed to unmount EFI partition"
    fi
    
    # Mount the EFI partition
    diskutil mount -mountPoint /Volumes/EFI "$EFI_DEVICE" || fatal "Failed to mount EFI partition"
    
    # Install rEFInd to the EFI partition
    info "Installing rEFInd to EFI partition..."
    refind-install --ownhfs /dev/disk0s1 || fatal "Failed to install rEFInd to EFI partition"
    
    # Create rEFInd configuration for Kali Linux
    info "Configuring rEFInd..."
    cat > "/Volumes/EFI/EFI/refind/refind.conf" <<EOL
timeout 20
use_graphics_for osx,linux
resolution 3
showtools shell,memtest,gdisk,csr_rotate,firmware,bootorder,about
scanfor manual,external,optical
default_selection macOS
dont_scan_dirs EFI/Microsoft

menuentry "macOS" {
    icon /EFI/refind/icons/os_mac.png
    volume "Macintosh HD"
    loader /System/Library/CoreServices/boot.efi
}

# Kali Linux entry will be added after installation
EOL
    
    success "rEFInd bootloader installed and configured."
}

prepare_disk() {
    print_step "3" "Preparing disk for Kali Linux"
    
    # Get the internal disk identifier (usually disk0)
    INTERNAL_DISK=$(diskutil list internal | grep -m 1 "^/dev/" | awk '{print $1}')
    
    if [[ -z "$INTERNAL_DISK" ]]; then
        fatal "Could not determine internal disk."
    fi
    
    info "Internal disk identified as: $INTERNAL_DISK"
    
    # Show disk information
    echo -e "\n${BLUE}${BOLD}Available disk space:${NC}"
    diskutil list "$INTERNAL_DISK"
    
    # Ask user to choose between using existing partition or creating a new one
    echo -e "\n${PURPLE}${BOLD}Installation Options:${NC}"
    options=("Create a new partition for Kali Linux" 
             "Use an existing partition (will format the selected partition)")
    
    echo "How would you like to install Kali Linux?"
    select_option "${options[@]}"
    choice=$?
    
    case $choice in
        0) # Create new partition
            # Ask for the size of the new partition
            read -p "Enter the size for Kali Linux partition in GB (minimum ${MIN_REQUIRED_SPACE} recommended, default ${DEFAULT_PARTITION_SIZE}): " PARTITION_SIZE
            
            # Use default if nothing entered
            if [[ -z "$PARTITION_SIZE" ]]; then
                PARTITION_SIZE=$DEFAULT_PARTITION_SIZE
            fi
            
            if [[ ! "$PARTITION_SIZE" =~ ^[0-9]+$ || "$PARTITION_SIZE" -lt $MIN_REQUIRED_SPACE ]]; then
                warning "Invalid size or less than ${MIN_REQUIRED_SPACE}GB specified."
                if ! confirm "Are you sure you want to continue with a ${PARTITION_SIZE}GB partition?"; then
                    fatal "Operation aborted by user."
                fi
            fi
            
            # Create a new partition
            info "Creating a new ${PARTITION_SIZE}GB partition for Kali Linux..."
            diskutil apfs resizeContainer "$INTERNAL_DISK"s1 0 "$PARTITION_SIZE"G ExFAT "Kali" || fatal "Failed to create partition"
            
            # Get the identifier of the new partition
            TARGET_PARTITION=$(diskutil list | grep "Kali" | awk '{print $NF}')
            
            if [[ -z "$TARGET_PARTITION" ]]; then
                fatal "Failed to identify the newly created partition."
            fi
            
            success "Created new partition: $TARGET_PARTITION"
            ;;
            
        1) # Use existing partition
            # List partitions for selection
            echo -e "\n${BLUE}${BOLD}Available partitions:${NC}"
            diskutil list "$INTERNAL_DISK"
            
            read -p "Enter the partition identifier (e.g., disk0s5): " TARGET_PARTITION
            
            # Verify the partition exists
            if ! diskutil info "$TARGET_PARTITION" &>/dev/null; then
                fatal "Partition $TARGET_PARTITION does not exist."
            fi
            
            info "Selected partition: $TARGET_PARTITION"
            
            # Check if the partition has data
            PARTITION_INFO=$(diskutil info "$TARGET_PARTITION")
            if echo "$PARTITION_INFO" | grep -q "Volume Name"; then
                warning "The selected partition appears to have data on it."
                warning "ALL DATA ON THIS PARTITION WILL BE ERASED!"
                if ! confirm "Are you ABSOLUTELY SURE you want to use this partition?"; then
                    fatal "Operation aborted by user."
                fi
            fi
            ;;
    esac
    
    # Format the partition as ExFAT temporarily (will be formatted as ext4 during installation)
    info "Formatting $TARGET_PARTITION as ExFAT..."
    diskutil eraseDisk ExFAT "KALI" "$TARGET_PARTITION" || fatal "Failed to format partition"
    
    success "Partition prepared for Kali Linux installation."
    echo "$TARGET_PARTITION" > "$WORK_DIR/target_partition"
}

install_kali() {
    print_step "4" "Installing Kali Linux"
    
    TARGET_PARTITION=$(cat "$WORK_DIR/target_partition")
    info "Installing Kali Linux to partition: $TARGET_PARTITION"
    
    # Mount the target partition
    MOUNT_POINT="/Volumes/KALI"
    if [[ ! -d "$MOUNT_POINT" ]]; then
        diskutil mount -mountPoint "$MOUNT_POINT" "$TARGET_PARTITION" || fatal "Failed to mount target partition"
    fi
    
    # Extract Kali Linux files to the target partition
    info "Extracting Kali Linux to the target partition..."
    info "This will take some time. Please be patient."
    
    # Create a mountpoint for the ISO
    ISO_MOUNT="/Volumes/KALI_ISO"
    mkdir -p "$ISO_MOUNT"
    
    # Mount the ISO
    hdiutil attach -mountpoint "$ISO_MOUNT" "$KALI_DISK_IMAGE" || fatal "Failed to mount Kali Linux ISO"
    
    # Copy files from ISO to target partition
    rsync -av "$ISO_MOUNT/" "$MOUNT_POINT/" || fatal "Failed to copy Kali Linux files"
    
    # Unmount ISO
    hdiutil detach "$ISO_MOUNT"
    
    # Install GRUB bootloader
    info "Installing GRUB bootloader..."
    
    # Create necessary directories
    mkdir -p "$MOUNT_POINT/boot/grub"
    
    # Generate GRUB configuration
    cat > "$MOUNT_POINT/boot/grub/grub.cfg" <<EOL
set default=0
set timeout=5

menuentry "Kali Linux" {
    linux /boot/vmlinuz root=/dev/$TARGET_PARTITION ro quiet splash
    initrd /boot/initrd.img
}
EOL
    
    # Unmount the target partition
    diskutil unmount "$MOUNT_POINT"
    
    success "Kali Linux installation completed successfully."
}

configure_dual_boot() {
    print_step "5" "Configuring dual boot"
    
    # Mount the EFI partition
    EFI_DEVICE=$(diskutil list | grep EFI | awk '{print $NF}')
    
    if [[ -z "$EFI_DEVICE" ]]; then
        fatal "Could not find EFI partition."
    fi
    
    # Create mount point if it doesn't exist
    mkdir -p /Volumes/EFI
    
    # Unmount if already mounted
    if mount | grep "/Volumes/EFI" &>/dev/null; then
        diskutil unmount /Volumes/EFI
    fi
    
    # Mount the EFI partition
    diskutil mount -mountPoint /Volumes/EFI "$EFI_DEVICE" || fatal "Failed to mount EFI partition"
    
    # Get the Kali Linux partition
    TARGET_PARTITION=$(cat "$WORK_DIR/target_partition")
    
    # Update rEFInd configuration
    info "Updating rEFInd configuration..."
    
    # Check if the entry already exists
    if grep -q "Kali Linux" "/Volumes/EFI/EFI/refind/refind.conf"; then
        info "Kali Linux entry already exists in rEFInd configuration."
    else
        # Append Kali Linux entry to rEFInd configuration
        cat >> "/Volumes/EFI/EFI/refind/refind.conf" <<EOL

menuentry "Kali Linux" {
    icon /EFI/refind/icons/os_linux.png
    volume "$TARGET_PARTITION"
    loader /boot/vmlinuz
    initrd /boot/initrd.img
    options "root=/dev/$TARGET_PARTITION ro quiet splash"
}
EOL
    fi
    
    success "Dual boot configuration updated."
    
    # Unmount EFI partition
    diskutil unmount /Volumes/EFI
}

complete_installation() {
    print_step "6" "Installation complete"
    
    # Clean up
    info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    
    echo -e "\n${GREEN}${BOLD}=== KALI LINUX INSTALLATION COMPLETED SUCCESSFULLY ===${NC}"
    echo -e "\n${BLUE}${BOLD}Next Steps:${NC}"
    echo "1. Restart your Mac."
    echo "2. Hold the power button until you see 'Loading startup options'."
    echo "3. You should see both macOS and Kali Linux in the boot menu."
    echo "4. Select Kali Linux to boot into your new installation."
    
    echo -e "\n${YELLOW}${BOLD}IMPORTANT NOTES:${NC}"
    echo "- Linux support on Apple Silicon is experimental and may have limitations."
    echo "- Wi-Fi, Bluetooth, and certain hardware features might require additional drivers."
    echo "- Always boot macOS occasionally to allow firmware updates."
    echo "- Complete log of this installation is available at: $LOG_FILE"
    
    echo -e "\n${GREEN}${BOLD}Enjoy your Kali Linux installation!${NC}"
}

# Main execution
main() {
    # Define total steps
    TOTAL_STEPS=6
    
    # Display header
    header
    
    # Check prerequisites
    check_sudo
    check_prerequisites
    
    # Confirm installation
    if ! confirm "Ready to install Kali Linux? This will modify your disk partitions and bootloader." "n"; then
        fatal "Installation aborted by user."
    fi
    
    # Execute installation steps
    download_kali
    install_bootloader
    prepare_disk
    install_kali
    configure_dual_boot
    complete_installation
}

# Run the main function
main "$@"
