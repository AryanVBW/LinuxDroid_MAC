#!/bin/bash
#
# mac_kali_dualboot.sh - Dual Boot Kali Linux Installation Script for macOS on Apple Silicon
# 
# This script sets up dual booting Kali Linux on macOS M3 and M3 Pro devices.
# IMPORTANT: This is an experimental process. Proceed with caution and backup all data.
#

set -e # Exit on error
set -o pipefail # Ensure pipes don't hide errors

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Log file setup
LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to log and display messages
display() {
    local level="$1"
    local color="$2"
    local message="$3"
    log "$level" "$message"
    echo -e "${color}${BOLD}[${level}]${NC} ${color}${message}${NC}"
}

# Function to display info messages
info() {
    display "INFO" "${BLUE}" "$1"
}

# Function to display success messages
success() {
    display "SUCCESS" "${GREEN}" "$1"
}

# Function to display warning messages
warning() {
    display "WARNING" "${YELLOW}" "$1"
}

# Function to display error messages
error() {
    display "ERROR" "${RED}" "$1"
}

# Function to exit with error
fatal() {
    error "$1"
    exit 1
}

# Function to confirm actions with the user
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

# Function to check if script is run with sudo
check_sudo() {
    info "Checking for administrative privileges..."
    if [[ $EUID -ne 0 ]]; then
        warning "This script requires administrative privileges."
        warning "Please run it again with sudo:"
        echo "sudo $0 $*"
        exit 1
    fi
    success "Administrative privileges confirmed."
}

# Function to check for M3/M3 Pro compatibility
check_compatibility() {
    info "Checking system compatibility..."
    
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
    
    # Try to determine if it's M3 or M3 Pro specifically
    if [[ "$chip" == *"M3"* ]]; then
        success "Compatible M3-series chip detected: $chip"
    else
        warning "This script is optimized for M3/M3 Pro chips. Your chip ($chip) may be compatible, but proceed with caution."
        if ! confirm "Do you want to continue anyway?"; then
            fatal "Installation aborted by user."
        fi
    fi
    
    # Check available disk space (need at least 30GB free)
    available_space=$(df -h / | awk 'NR==2 {print $4}' | sed 's/Gi//')
    info "Available disk space: ${available_space}GB"
    
    if (( $(echo "$available_space < 30" | bc -l) )); then
        warning "You have less than 30GB of free space. Kali Linux installation requires at least 30GB."
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
    
    success "System compatibility check completed."
}

# Function to download and verify Kali Linux ISO
download_kali() {
    info "Preparing to download Kali Linux for ARM64..."
    
    # Define the URL for Kali ARM64
    KALI_URL="https://cdimage.kali.org/kali-2025.1c/kali-linux-2025.1c-installer-arm64.iso"
    KALI_SHA256_URL="https://cdimage.kali.org/kali-2025.1c/SHA256SUMS"
    KALI_ISO=$(basename "$KALI_URL")
    
    # Define the download directory
    DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DOWNLOAD_DIR"
    
    # Check if ISO already exists
    if [[ -f "$DOWNLOAD_DIR/$KALI_ISO" ]]; then
        info "Kali Linux ISO already exists at $DOWNLOAD_DIR/$KALI_ISO"
        if confirm "Do you want to download it again?"; then
            rm "$DOWNLOAD_DIR/$KALI_ISO"
        else
            info "Using existing ISO file."
            SKIP_DOWNLOAD=true
        fi
    fi
    
    # Download the ISO if needed
    if [[ "$SKIP_DOWNLOAD" != true ]]; then
        info "Downloading Kali Linux ISO from $KALI_URL..."
        info "This may take a while depending on your internet connection."
        curl -L "$KALI_URL" -o "$DOWNLOAD_DIR/$KALI_ISO" || fatal "Failed to download Kali Linux ISO"
        success "Download completed."
    fi
    
    # Download SHA256SUMS file
    info "Downloading SHA256SUMS file to verify the ISO..."
    curl -L "$KALI_SHA256_URL" -o "$DOWNLOAD_DIR/SHA256SUMS" || fatal "Failed to download SHA256SUMS file"
    
    # Verify the ISO checksum
    info "Verifying ISO checksum..."
    expected_sha256=$(grep "$KALI_ISO" "$DOWNLOAD_DIR/SHA256SUMS" | awk '{print $1}')
    
    if [[ -z "$expected_sha256" ]]; then
        warning "Could not find the expected SHA256 hash for $KALI_ISO in the SHA256SUMS file."
        warning "This could mean the ISO name has changed or the SHA256SUMS file format has changed."
        if ! confirm "Do you want to continue without verification?"; then
            fatal "Installation aborted due to verification failure."
        fi
    else
        actual_sha256=$(shasum -a 256 "$DOWNLOAD_DIR/$KALI_ISO" | awk '{print $1}')
        
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
    
    # Return the path to the ISO file
    echo "$DOWNLOAD_DIR/$KALI_ISO"
}

# Function to install bootloader
install_bootloader() {
    info "Preparing to install bootloader for dual boot..."
    
    # Check if rEFInd is already installed
    if [[ -d "/EFI/refind" ]] || [[ -d "/usr/local/bin/refind-install" ]]; then
        info "rEFInd appears to be already installed."
        if ! confirm "Do you want to reinstall it?"; then
            info "Skipping rEFInd installation."
            return
        fi
    fi
    
    # Install Homebrew if not already installed
    if ! command -v brew &>/dev/null; then
        info "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fatal "Failed to install Homebrew"
        success "Homebrew installed successfully."
    else
        info "Homebrew is already installed."
    fi
    
    # Install rEFInd via Homebrew
    info "Installing rEFInd bootloader..."
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
    info "Configuring rEFInd for Kali Linux..."
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

# Function to partition the disk for Kali
partition_disk() {
    info "Preparing to create a partition for Kali Linux..."
    
    # List all disks
    info "Available disks:"
    diskutil list
    
    # Get the internal disk identifier (usually disk0)
    INTERNAL_DISK=$(diskutil list internal | grep -m 1 "^/dev/" | awk '{print $1}')
    
    if [[ -z "$INTERNAL_DISK" ]]; then
        fatal "Could not determine internal disk."
    fi
    
    info "Internal disk identified as: $INTERNAL_DISK"
    
    # Option 1: Use existing partition
    echo -e "\n${BLUE}${BOLD}OPTION 1: Use an existing partition${NC}"
    echo "If you have already created a partition for Kali Linux, you can select it here."
    echo "Otherwise, choose Option 2 to create a new partition."
    
    if confirm "Do you want to use an existing partition?"; then
        # List partitions for selection
        diskutil list "$INTERNAL_DISK"
        
        read -p "Enter the partition identifier (e.g., disk0s5): " SELECTED_PARTITION
        
        # Verify the partition exists
        if ! diskutil info "$SELECTED_PARTITION" &>/dev/null; then
            fatal "Partition $SELECTED_PARTITION does not exist."
        fi
        
        info "Selected partition: $SELECTED_PARTITION"
        
        # Check if the partition has data
        PARTITION_INFO=$(diskutil info "$SELECTED_PARTITION")
        if echo "$PARTITION_INFO" | grep -q "Volume Name"; then
            warning "The selected partition appears to have data on it."
            warning "ALL DATA ON THIS PARTITION WILL BE ERASED!"
            if ! confirm "Are you ABSOLUTELY SURE you want to use this partition?"; then
                fatal "Operation aborted by user."
            fi
        fi
    else
        # Option 2: Create a new partition
        echo -e "\n${BLUE}${BOLD}OPTION 2: Create a new partition${NC}"
        
        # Check free space
        free_space=$(diskutil info "$INTERNAL_DISK" | grep "Free Space" | awk '{print $4}' | sed 's/\..*$//')
        
        if [[ -z "$free_space" || "$free_space" -lt 30 ]]; then
            warning "There may not be enough free space to create a new partition."
            warning "You should resize your macOS partition using Disk Utility first."
            
            if ! confirm "Do you still want to attempt to create a new partition?"; then
                fatal "Operation aborted by user."
            fi
        fi
        
        # Ask for the size of the new partition
        read -p "Enter the size for Kali Linux partition in GB (minimum 30 recommended): " PARTITION_SIZE
        
        if [[ ! "$PARTITION_SIZE" =~ ^[0-9]+$ || "$PARTITION_SIZE" -lt 20 ]]; then
            warning "Invalid size or less than 20GB specified."
            if ! confirm "Are you sure you want to continue with a ${PARTITION_SIZE}GB partition?"; then
                fatal "Operation aborted by user."
            fi
        fi
        
        # Create a new partition
        info "Creating a new ${PARTITION_SIZE}GB partition for Kali Linux..."
        diskutil apfs resizeContainer "$INTERNAL_DISK"s1 0 "$PARTITION_SIZE"G ExFAT "Kali" || fatal "Failed to create partition"
        
        # Get the identifier of the new partition
        SELECTED_PARTITION=$(diskutil list | grep "Kali" | awk '{print $NF}')
        
        if [[ -z "$SELECTED_PARTITION" ]]; then
            fatal "Failed to identify the newly created partition."
        fi
        
        success "Created new partition: $SELECTED_PARTITION"
    fi
    
    # Format the partition as ExFAT temporarily (will be formatted as ext4 during installation)
    info "Formatting $SELECTED_PARTITION as ExFAT temporarily..."
    diskutil eraseDisk ExFAT "KALI" "$SELECTED_PARTITION" || fatal "Failed to format partition"
    
    success "Partition prepared for Kali Linux installation."
    echo "$SELECTED_PARTITION"
}

# Function to prepare USB installer
prepare_usb() {
    local kali_iso="$1"
    
    info "Preparing USB installer for Kali Linux..."
    
    # List all external disks
    info "Available external disks:"
    diskutil list external
    
    echo -e "\n${YELLOW}${BOLD}IMPORTANT: ALL DATA ON THE SELECTED USB DRIVE WILL BE ERASED!${NC}"
    echo "Please connect the USB drive you want to use for Kali Linux installation."
    echo "The USB drive should be at least 8GB in size."
    
    read -p "Enter the USB disk identifier (e.g., disk2): " USB_DISK
    
    # Verify it's an external disk
    if ! diskutil list external | grep -q "$USB_DISK"; then
        fatal "Disk $USB_DISK is not an external disk or does not exist."
    fi
    
    # Verify disk is a USB drive and not something else
    diskutil info "$USB_DISK" | grep "Protocol" | grep -q "USB" || \
        fatal "Disk $USB_DISK does not appear to be a USB device. Aborting for safety."
    
    # Confirm before proceeding
    warning "ALL DATA ON $USB_DISK WILL BE ERASED!"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?"; then
        fatal "Operation aborted by user."
    fi
    
    # Unmount all partitions on the USB disk
    info "Unmounting all partitions on $USB_DISK..."
    diskutil unmountDisk force "$USB_DISK" || fatal "Failed to unmount disk $USB_DISK"
    
    # Use dd to write the ISO to the USB disk
    info "Writing Kali Linux ISO to USB disk using dd..."
    info "This will take some time. Please be patient."
    
    # Use pv if available for progress updates
    if command -v pv &>/dev/null; then
        (pv -pterb "$kali_iso" | sudo dd of="/dev/$USB_DISK" bs=1m) 2>&1 || \
            fatal "Failed to write ISO to USB disk"
    else
        sudo dd if="$kali_iso" of="/dev/$USB_DISK" bs=1m status=progress || \
            fatal "Failed to write ISO to USB disk"
    fi
    
    # Eject the USB disk
    diskutil eject "$USB_DISK" || warning "Could not eject $USB_DISK. You may need to eject it manually."
    
    success "Kali Linux USB installer created successfully."
}

# Function to provide installation instructions
provide_instructions() {
    local partition="$1"
    
    echo -e "\n${GREEN}${BOLD}=== KALI LINUX INSTALLATION INSTRUCTIONS ===${NC}"
    echo -e "\n${BLUE}${BOLD}Step 1: Boot from USB${NC}"
    echo "1. Shut down your Mac."
    echo "2. Connect the Kali Linux USB installer."
    echo "3. Turn on your Mac while holding the power button until you see 'Loading startup options'."
    echo "4. Select the USB drive from the startup options."
    
    echo -e "\n${BLUE}${BOLD}Step 2: Install Kali Linux${NC}"
    echo "1. Follow the Kali Linux installation wizard."
    echo "2. When prompted for installation destination, select the partition you prepared:"
    echo "   - The partition identifier was: $partition"
    echo "   - It will appear as an ExFAT drive labeled 'KALI'"
    echo "3. Format this partition as ext4 during the installation process."
    echo "4. Complete the installation, but DO NOT install GRUB to the main disk's MBR."
    echo "   - Instead, install GRUB to the partition you created for Kali."
    
    echo -e "\n${BLUE}${BOLD}Step 3: Configure Dual Boot${NC}"
    echo "1. After installation, boot back into macOS."
    echo "2. Run this script again with the --configure-dual-boot option."
    echo "   - This will update the rEFInd configuration to include Kali Linux."
    
    echo -e "\n${YELLOW}${BOLD}IMPORTANT NOTES:${NC}"
    echo "- Linux support on Apple Silicon is experimental and may have limitations."
    echo "- Wi-Fi, Bluetooth, and certain hardware features might require additional drivers."
    echo "- Always boot macOS occasionally to allow firmware updates."
    echo "- Complete log of this setup is available at: $LOG_FILE"
    
    echo -e "\n${GREEN}${BOLD}Installation preparation complete!${NC}"
}

# Function to configure dual boot after Kali is installed
configure_dual_boot() {
    info "Configuring dual boot for Kali Linux..."
    
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
    
    # Find the Kali Linux partition
    KALI_PARTITION=$(diskutil list | grep -i "linux" | awk '{print $NF}')
    
    if [[ -z "$KALI_PARTITION" ]]; then
        warning "Could not automatically find Kali Linux partition."
        diskutil list
        read -p "Enter the Kali Linux partition identifier (e.g., disk0s5): " KALI_PARTITION
    fi
    
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
    volume "$KALI_PARTITION"
    loader /boot/vmlinuz
    initrd /boot/initrd.img
    options "root=/dev/$KALI_PARTITION ro quiet splash"
}
EOL
    fi
    
    success "Dual boot configuration updated."
    
    # Unmount EFI partition
    diskutil unmount /Volumes/EFI
    
    info "Dual boot has been configured. You should now be able to boot into either macOS or Kali Linux."
    info "When you restart your Mac, you'll see the rEFInd boot menu."
    info "Select 'macOS' to boot into macOS or 'Kali Linux' to boot into Kali Linux."
}

# Main script execution
main() {
    echo -e "${GREEN}${BOLD}===== Apple Silicon Mac (M3/M3 Pro) Kali Linux Dual Boot Setup =====${NC}"
    echo -e "${YELLOW}This script will help you set up dual booting Kali Linux on your Apple Silicon Mac.${NC}"
    echo -e "${RED}${BOLD}WARNING: This is an experimental process. Proceed with caution.${NC}"
    echo -e "${RED}${BOLD}BACKUP ALL IMPORTANT DATA BEFORE PROCEEDING!${NC}\n"
    
    # Check for the --configure-dual-boot flag
    if [[ "$1" == "--configure-dual-boot" ]]; then
        check_sudo
        configure_dual_boot
        exit 0
    fi
    
    # Ask for confirmation before proceeding
    if ! confirm "Do you want to proceed with the Kali Linux dual boot setup?"; then
        info "Setup aborted by user."
        exit 0
    fi
    
    # Check if script is running with sudo privileges
    check_sudo
    
    # Check system compatibility
    check_compatibility
    
    # Download and verify Kali Linux ISO
    KALI_ISO=$(download_kali)
    
    # Install and configure bootloader
    install_bootloader
    
    # Partition disk for Kali
    KALI_PARTITION=$(partition_disk)
    
    # Prepare USB installer
    prepare_usb "$KALI_ISO"
    
    # Provide installation instructions
    provide_instructions "$KALI_PARTITION"
}

# Run the main function
main "$@"
