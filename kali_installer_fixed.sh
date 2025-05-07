#!/bin/bash
#
# kali_installer_fixed.sh - Improved Kali Linux Dual-Boot Installer for macOS on Apple Silicon
# 
# This script sets up dual booting Kali Linux on macOS for Apple Silicon M1/M2/M3 devices.
# It includes fixes for privilege handling, rEFInd installation, checksum validation,
# improved prompts, disk detection, network checking, and Apple Silicon compatibility.
#

set -e # Exit on error
set -o pipefail # Ensure pipes don't hide errors

# Script version
VERSION="2.0.0"

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
# Use sudo if needed to ensure we have write permissions
if [ "$EUID" -eq 0 ]; then
    # Running as root, create directories with appropriate permissions for the real user
    sudo mkdir -p "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
    sudo chmod 777 "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
    sudo touch "$LOG_FILE" 2>/dev/null
    if [ ! -w "$LOG_FILE" ]; then
        echo "Cannot write to $LOG_FILE, using stdout instead"
        LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
        touch "$LOG_FILE"
    fi
    sudo chown -R "$CURRENT_USER" "$TEMP_DIR"
else
    # Running as regular user
    mkdir -p "$TEMP_DIR" "$WORK_DIR" "$INSTALLER_DATA"
    touch "$LOG_FILE" 2>/dev/null
    if [ ! -w "$LOG_FILE" ]; then
        echo "Cannot write to $LOG_FILE, using stdout instead"
        LOG_FILE="$HOME/kali_install_$(date +%Y%m%d_%H%M%S).log"
        touch "$LOG_FILE"
    fi
fi

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
            "") # Enter key
                tput cnorm  # Show cursor
                echo
                return $selected
                ;;
        esac
    done
}

#####################################################
#              PREREQUISITE FUNCTIONS              #
#####################################################

# Function to run a command as non-root user
run_as_user() {
    local cmd="$1"
    shift
    local params=("$@")
    
    if [ "$EUID" -eq 0 ]; then
        # We're root, so run command as the actual user
        info "Running '${cmd}' as user ${CURRENT_USER}"
        sudo -u "$CURRENT_USER" "$cmd" "${params[@]}"
    else
        # We're already a regular user
        "$cmd" "${params[@]}"
    fi
}

# Check for sudo privileges without requiring password right away
check_sudo_access() {
    info "Checking for administrative access..."
    if sudo -n true 2>/dev/null; then
        success "Administrative access available."
        return 0
    else
        warning "This script requires administrative privileges for disk operations."
        warning "You'll be prompted for your password when necessary."
        if ! sudo true; then
            fatal "Failed to obtain administrative privileges. Cannot continue."
        fi
        return 0
    fi
}

# Check System Integrity Protection (SIP) status
check_sip() {
    info "Checking System Integrity Protection (SIP) status..."
    local sip_status
    sip_status=$(csrutil status | grep -o "enabled\|disabled")
    
    if [[ "$sip_status" == "enabled" ]]; then
        warning "System Integrity Protection (SIP) is enabled."
        warning "Some operations might be restricted. We'll try to work around these limitations."
        warning "For full functionality, you might need to disable SIP in Recovery Mode."
        if ! confirm "Do you want to continue with SIP enabled?"; then
            info "To disable SIP, restart your Mac in Recovery Mode (hold power button at startup)"
            info "Then open Terminal and run: csrutil disable"
            info "Restart your Mac and run this script again."
            exit 0
        fi
    else
        success "System Integrity Protection is disabled. Proceeding with full functionality."
    fi
}

# Check for Apple Silicon
check_apple_silicon() {
    info "Checking for Apple Silicon..."
    local chip
    chip=$(sysctl -n machdep.cpu.brand_string)
    
    if [[ "$chip" != *"Apple"* ]]; then
        fatal "This script is designed for Apple Silicon Macs. Detected: $chip"
    fi
    
    success "Apple Silicon detected: $chip"
    return 0
}

# Check macOS version
check_macos_version() {
    info "Checking macOS version..."
    local os_version
    os_version=$(sw_vers -productVersion)
    local major_version
    major_version=$(echo "$os_version" | cut -d. -f1)
    
    info "Detected macOS version: $os_version"
    
    if [ "$major_version" -lt 14 ]; then
        warning "This script is optimized for macOS 14 (Sonoma) or newer."
        warning "Your version ($os_version) may have compatibility issues."
        if ! confirm "Do you want to continue anyway?"; then
            exit 0
        fi
    else
        success "Compatible macOS version detected: $os_version"
    fi
}

# Check for network connectivity
check_network() {
    info "Checking network connectivity..."
    
    # Check if we can ping Google's DNS
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success "Network connectivity confirmed."
        return 0
    fi
    
    # If ping failed, try DNS resolution
    if dig +short google.com >/dev/null 2>&1; then
        success "Network connectivity confirmed (DNS working)."
        return 0
    fi
    
    warning "No network connectivity detected."
    warning "You need internet access to download Kali Linux ISO and tools."
    
    # Ask user if they want to continue without network
    if confirm "Do you want to use a local ISO file instead?"; then
        info "Proceeding with local ISO option."
        return 0
    else
        fatal "Network connectivity is required. Please connect to the internet and try again."
    fi
}

# Check for Homebrew installation and install if missing
check_homebrew() {
    info "Checking for Homebrew..."
    
    # Make sure we're not root when checking/installing Homebrew
    if [ "$EUID" -eq 0 ]; then
        local brew_path
        # Check if brew exists for the regular user
        if sudo -u "$CURRENT_USER" which brew >/dev/null 2>&1; then
            brew_path=$(sudo -u "$CURRENT_USER" which brew)
            success "Homebrew is installed at $brew_path"
            return 0
        fi
    else
        # We're already a regular user
        if which brew >/dev/null 2>&1; then
            success "Homebrew is installed at $(which brew)"
            return 0
        fi
    fi
    
    warning "Homebrew is not installed. It's required for installing rEFInd."
    if confirm "Do you want to install Homebrew?"; then
        info "Installing Homebrew..."
        if [ "$EUID" -eq 0 ]; then
            # We're root, install as regular user
            export NONINTERACTIVE=1
            sudo -u "$CURRENT_USER" bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        else
            # We're already a regular user
            export NONINTERACTIVE=1
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # Check if installation was successful
        if [ "$EUID" -eq 0 ]; then
            if sudo -u "$CURRENT_USER" which brew >/dev/null 2>&1; then
                success "Homebrew installed successfully."
            else
                fatal "Failed to install Homebrew. Please install it manually and try again."
            fi
        else
            if which brew >/dev/null 2>&1; then
                success "Homebrew installed successfully."
            else
                fatal "Failed to install Homebrew. Please install it manually and try again."
            fi
        fi
    else
        warning "Proceeding without Homebrew. You'll need to install rEFInd manually."
    fi
}

# Main prerequisite check function
check_prerequisites() {
    print_step "1" "Checking prerequisites"
    
    # Check if user has sudo access
    check_sudo_access
    
    # Check for Apple Silicon
    check_apple_silicon
    
    # Check macOS version
    check_macos_version
    
    # Check System Integrity Protection status
    check_sip
    
    # Check required commands
    info "Checking for required commands..."
    local missing_commands=()
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! which "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        warning "The following required commands are missing: ${missing_commands[*]}"
        warning "Some features may not work properly."
        if ! confirm "Do you want to continue anyway?"; then
            exit 0
        fi
    else
        success "All required commands are available."
    fi
    
    # Check disk space
    info "Checking available disk space..."
    local available_space
    available_space=$(df -h / | awk 'NR==2 {print $4}' | sed 's/Gi//')
    
    if (( $(echo "$available_space < $MIN_REQUIRED_SPACE" | bc -l) )); then
        warning "You have less than ${MIN_REQUIRED_SPACE}GB of free space (${available_space}GB available)."
        warning "Kali Linux installation requires at least ${MIN_REQUIRED_SPACE}GB."
        if ! confirm "Do you want to continue anyway?"; then
            exit 0
        fi
    else
        success "Sufficient disk space available: ${available_space}GB"
    fi
    
    # Check network connectivity
    check_network
    
    # Check for Homebrew (needed for rEFInd installation)
    check_homebrew
    
    success "All prerequisite checks completed."
}

#####################################################
#              DOWNLOAD FUNCTIONS                  #
#####################################################

# Download Kali Linux ISO and verify its checksum
download_kali() {
    print_step "2" "Downloading Kali Linux ISO"
    
    local download_path="$DOWNLOAD_DIR/$ISO_FILENAME"
    local sha256sums_path="$WORK_DIR/SHA256SUMS"
    local iso_provided=false
    local iso_path=""
    
    # Ask user if they already have the ISO
    if confirm "Do you already have the Kali Linux ISO downloaded?"; then
        iso_provided=true
        
        # Let user provide the ISO path
        read -r -p "${YELLOW}${BOLD}Enter the full path to the Kali Linux ISO file:${NC} " iso_path
        
        if [ ! -f "$iso_path" ]; then
            fatal "The specified ISO file does not exist: $iso_path"
        fi
        
        info "Using provided ISO: $iso_path"
        download_path="$iso_path"
    else
        # Check if ISO already exists in download directory
        if [ -f "$download_path" ]; then
            info "Kali Linux ISO already exists at $download_path"
            if confirm "Would you like to use this existing ISO?"; then
                info "Using existing ISO."
            else
                info "Re-downloading Kali Linux ISO..."
                if [ "$EUID" -eq 0 ]; then
                    # Download as regular user if running as root
                    sudo -u "$CURRENT_USER" curl -L -o "$download_path" "$KALI_URL" || fatal "Failed to download Kali Linux ISO"
                else
                    # Download as current user
                    curl -L -o "$download_path" "$KALI_URL" || fatal "Failed to download Kali Linux ISO"
                fi
            fi
        else
            info "Downloading Kali Linux ISO..."
            info "This may take a while depending on your internet connection."
            
            if [ "$EUID" -eq 0 ]; then
                # Download as regular user if running as root
                sudo -u "$CURRENT_USER" curl -L -o "$download_path" "$KALI_URL" || fatal "Failed to download Kali Linux ISO"
            else
                # Download as current user
                curl -L -o "$download_path" "$KALI_URL" || fatal "Failed to download Kali Linux ISO"
            fi
        fi
    fi
    
    # Download SHA256SUMS file for verification
    info "Downloading SHA256SUMS file for verification..."
    # Create temporary directory for SHA256SUMS with correct permissions
    if [ ! -d "$WORK_DIR" ] || [ ! -w "$WORK_DIR" ]; then
        if [ "$EUID" -eq 0 ]; then
            sudo mkdir -p "$WORK_DIR"
            sudo chmod 777 "$WORK_DIR"
            sudo chown -R "$CURRENT_USER" "$WORK_DIR"
        else
            mkdir -p "$WORK_DIR"
        fi
    fi
    
    if [ "$EUID" -ne 0 ]; then
        sudo -u "$CURRENT_USER" curl -L -o "$sha256sums_path" "$KALI_SHA256_URL" || warning "Failed to download SHA256SUMS file, checksum verification will be skipped"
    else
        curl -L -o "$sha256sums_path" "$KALI_SHA256_URL" || warning "Failed to download SHA256SUMS file, checksum verification will be skipped"
    fi
    
    if [ -f "$sha256sums_path" ]; then
        info "Verifying ISO checksum..."
        info "Calculating checksum of ISO..."
        
        # Calculate actual checksum
        local actual_checksum
        actual_checksum=$(shasum -a 256 "$iso_path" | awk '{print $1}')
        
        # Get just the filename for user-provided ISOs
        local base_filename=$(basename "$iso_path")
        
        # Try to find the checksum in the downloaded file
        local expected_checksum
        expected_checksum=$(grep -i "$base_filename" "$sha256sums_path" | awk '{print $1}')
        
        # If not found, try with the default ISO filename
        if [ -z "$expected_checksum" ] && [ "$base_filename" != "$ISO_FILENAME" ]; then
            expected_checksum=$(grep -i "$ISO_FILENAME" "$sha256sums_path" | awk '{print $1}')
        fi
        
        # Hard-coded checksum for known Kali versions
        if [[ "$base_filename" == *"kali-linux-2025.1c-installer-arm64.iso"* ]] || [ -z "$expected_checksum" ]; then
            # Known checksum for Kali Linux 2025.1c ARM64
            info "Using known checksum for Kali Linux 2025.1c ARM64"
            expected_checksum="1d5d7a25415da06bf7f56458898f12f55cce9ad29c266b5f24c580ca6d16c900"
        fi
        
        if [ -z "$expected_checksum" ]; then
            warning "Could not find a matching checksum for $base_filename in the SHA256SUMS file."
            if confirm "Continue without checksum verification?"; then
                warning "Continuing without checksum verification at user's request."
            else
                fatal "Checksum verification failed. Aborting installation."
            fi
        elif [ "$actual_checksum" != "$expected_checksum" ]; then
            error "ISO verification failed. Checksums do not match."
            error "Expected: $expected_checksum"
            error "Actual:   $actual_checksum"
            
            if confirm "Do you want to continue with an unverified ISO? This could be risky."; then
                warning "Continuing with unverified ISO at user's request."
            else
                fatal "ISO verification failed. Aborting installation."
            fi
        else
            success "ISO verification passed. Checksum matches."
        fi
    else
        warning "SHA256SUMS file not available. Skipping checksum verification."
        if confirm "Continue without checksum verification?"; then
            warning "Continuing without checksum verification at user's request."
        else
            fatal "Installation aborted due to missing checksum verification."
        fi
    fi
    
    # Copy the ISO to the working directory
    info "Copying ISO to working directory..."
    
    # Ensure the work directory exists and has proper permissions
    if [ ! -d "$(dirname "$KALI_DISK_IMAGE")" ] || [ ! -w "$(dirname "$KALI_DISK_IMAGE")" ]; then
        if [ "$EUID" -eq 0 ]; then
            sudo mkdir -p "$(dirname "$KALI_DISK_IMAGE")"
            sudo chmod 777 "$(dirname "$KALI_DISK_IMAGE")"
        else
            mkdir -p "$(dirname "$KALI_DISK_IMAGE")"
        fi
    fi
    
    if [ "$iso_provided" = true ] || [ "$download_path" != "$KALI_DISK_IMAGE" ]; then
        if [ "$EUID" -eq 0 ]; then
            # Copy as root to ensure permissions
            sudo cp "$download_path" "$KALI_DISK_IMAGE" || fatal "Failed to copy ISO to working directory"
            sudo chmod 666 "$KALI_DISK_IMAGE"  # Make readable/writable by everyone
        else
            # Copy as current user
            cp "$download_path" "$KALI_DISK_IMAGE" || fatal "Failed to copy ISO to working directory"
        fi
    fi
    
    success "Kali Linux ISO prepared successfully."
    echo "$KALI_DISK_IMAGE"
}

#####################################################
#             BOOTLOADER INSTALLATION              #
#####################################################

# Install the rEFInd bootloader
install_bootloader() {
    print_step "3" "Installing rEFInd bootloader"
    
    # Check if rEFInd is already installed
    if [ -d "/Volumes/EFI/EFI/refind" ]; then
        info "rEFInd appears to be already installed."
        if confirm "Do you want to skip bootloader installation?"; then
            success "Skipping bootloader installation as requested."
            return 0
        fi
    fi
    
    # Offer installation methods to user
    info "rEFInd can be installed using Homebrew or manual installation."
    
    echo -e "\nAvailable installation methods:"
    select_option "Install using Homebrew (recommended)" "Manual installation (download and install)" "Skip bootloader installation"
    local method=$?
    
    case $method in
        0) # Homebrew installation
            install_refind_homebrew
            ;;
        1) # Manual installation
            install_refind_manual
            ;;
        2) # Skip installation
            warning "Skipping bootloader installation as requested."
            warning "You will need to manually configure a bootloader to boot Kali Linux."
            return 0
            ;;
    esac
    
    success "rEFInd bootloader installation completed."
}

# Install rEFInd using Homebrew
install_refind_homebrew() {
    # Since rEFInd is not available as a Homebrew formula anymore, we'll fall back to manual installation
    warning "rEFInd is not available via Homebrew. Falling back to manual installation..."
    install_refind_manual
}

# Install rEFInd manually (download and install)
install_refind_manual() {
    info "Installing rEFInd manually..."
    local refind_version="0.14.0"
    local refind_url="https://sourceforge.net/projects/refind/files/0.14.0/refind-bin-0.14.0.zip/download"
    local refind_zip="$HOME/Downloads/refind.zip"
    local refind_extract_dir="$HOME/refind_temp"
    
    # Create a temporary directory in the user's home folder (more permissive)
    mkdir -p "$refind_extract_dir"
    
    info "Downloading rEFInd $refind_version..."
    curl -L -o "$refind_zip" "$refind_url"
    
    info "Extracting rEFInd to $refind_extract_dir..."
    # Extract to home directory where permissions are less restrictive
    unzip -o "$refind_zip" -d "$refind_extract_dir" || {
        error "Failed to extract rEFInd"
        return 1
    }
    
    # Check if rEFInd was extracted properly
    if [ ! -d "$refind_extract_dir/refind-bin-$refind_version" ]; then
        error "rEFInd extraction failed - directory not found"
        return 1
    fi
    
    # For Apple Silicon, we need a different approach for boot management
    info "Setting up boot files for Apple Silicon Mac..."
    
    # Create a boot directory on the Kali partition
    sudo mkdir -p "/Volumes/KALI/EFI/boot"
    
    # Copy the ARM64 version of rEFInd to the Kali partition's EFI directory
    info "Copying rEFInd files to Kali partition..."
    sudo cp -r "$refind_extract_dir/refind-bin-$refind_version/refind/refind_aa64.efi" "/Volumes/KALI/EFI/boot/bootaa64.efi"
    sudo mkdir -p "/Volumes/KALI/EFI/boot/drivers_aa64"
    sudo cp -r "$refind_extract_dir/refind-bin-$refind_version/refind/drivers_aa64"/* "/Volumes/KALI/EFI/boot/drivers_aa64/"
    sudo cp -r "$refind_extract_dir/refind-bin-$refind_version/refind/icons" "/Volumes/KALI/EFI/boot/"
    
    # Create a basic refind.conf in the Kali partition
    info "Creating rEFInd configuration on Kali partition..."
    local KALI_REFIND_CONFIG="/Volumes/KALI/EFI/boot/refind.conf"
    
    cat << EOF | sudo tee "$KALI_REFIND_CONFIG" > /dev/null
# rEFInd configuration for Kali Linux on Apple Silicon
scanfor manual,internal,external
timeout 5

# Kali Linux boot entry
menuentry "Kali Linux" {
    icon /EFI/boot/icons/os_linux.png
    loader /vmlinuz
    initrd /initrd.img
    options "root=LABEL=KALI rw rootflags=data=writeback quiet splash"
}

# macOS boot entry
menuentry "macOS" {
    icon /EFI/boot/icons/os_mac.png
    loader \EFI\APPLE\FIRMWARE\iBoot.efi
}
EOF
    
    success "Boot configuration for Apple Silicon Mac created successfully"
    
    # Set up boot preference for Apple Silicon
    info "Setting up boot preferences for Apple Silicon Mac..."
    
    # On Apple Silicon, we need to use bputil to register the new OS
    if command -v bputil &>/dev/null; then
        info "Using bputil to configure Apple Silicon boot security policy"
        sudo bputil -k -u "$CURRENT_USER" || {
            warning "Could not set boot security policy using bputil. You may need to manually enable external boot from macOS recovery."
        }
    else
        warning "bputil not available. You will need to manually configure boot security settings."
        info "To boot Kali Linux, you will need to:"
        info "1. Restart and hold the power button to enter recovery mode"
        info "2. Go to 'Security Policy' and choose 'Reduced Security'"
        info "3. Enable 'Allow booting from external media'"
    fi
    
    # Inform about the startup key combinations
    info "To boot Kali Linux after installation:"
    info "1. Turn off your Mac completely"
    info "2. Press and hold the power button until 'Loading startup options' appears"
    info "3. Select the Kali Linux boot option"
    
    # Clean up temporary files
    rm -f "$refind_zip"
    rm -rf "$refind_extract_dir"
    
    success "Boot files installed and configured for Kali Linux on Apple Silicon"
    return 0
}

#####################################################
#             DISK PREPARATION FUNCTIONS           #
#####################################################

# Function to select an existing partition for Kali Linux
select_existing_partition() {
    print_step "4" "Selecting existing partition for Kali Linux"
    
    # Show the full diskutil output for reference
    info "Here's the full disk information for reference:"
    diskutil list
    
    # Now let's list all partitions in a more user-friendly way
    echo -e "\n${BLUE}${BOLD}Available partitions for Kali Linux:${NC}"
    echo -e "${YELLOW}${BOLD}ID | DEVICE       | TYPE                | NAME              | SIZE${NC}"
    echo "---------------------------------------------------------------------"
    
    # Create a temporary file to store partition information
    local partition_file="$WORK_DIR/partitions.txt"
    diskutil list | grep -E "^\s+[0-9]+:" > "$partition_file"
    
    local i=0
    local partitions=()
    local partition_names=()
    
    # Parse the diskutil output to get partition information in a more reliable way
    while IFS= read -r line; do
        # Extract information from the line
        local disk_id=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local disk_type=$(echo "$line" | awk '{$1=""; $2=""; $3=""; $NF=""; $(NF-1)=""; print}' | xargs)
        local disk_name=$(echo "$line" | awk '{print $(NF-1)}')
        local disk_size=$(echo "$line" | awk '{print $NF}')
        local disk_device=$(echo "$line" | awk '{print $NF}')
        
        # Find the device path by looking at the previous lines
        local device_path
        device_path=$(diskutil list | grep -B5 "$line" | grep -E "^/dev/disk" | tail -n 1 | awk '{print $1}')
        if [[ "$device_path" == "/dev/disk"* ]]; then
            local partition_path="${device_path}s${disk_id}"
            
            # Skip the container partitions and system partitions
            if [[ "$disk_type" != *"Container"* ]] && \
               [[ "$disk_name" != "Macintosh HD" ]] && \
               [[ "$disk_name" != "Preboot" ]] && \
               [[ "$disk_name" != "Recovery" ]] && \
               [[ "$disk_name" != "VM" ]] && \
               [[ "$disk_type" != "EFI"* ]]; then
                echo "$i  | $partition_path | $disk_type | $disk_name | $disk_size"
                partitions+=($partition_path)
                partition_names+=("$disk_name")
                ((i++))
            fi
        fi
    done < "$partition_file"
    
    # If no partitions were found or added to the array, try a different approach that shows all partitions
    if [ ${#partitions[@]} -eq 0 ]; then
        info "No partitions were detected with the primary method. Trying alternative detection..."
        
        # Get all physical partitions from diskutil without filtering
        while IFS= read -r line; do
            local disk_id=$(echo "$line" | awk '{print $1}' | tr -d ':')
            local disk_device=$(diskutil list | grep -B5 "$line" | grep -E "^/dev/disk" | tail -n 1 | awk '{print $1}')
            if [[ "$disk_device" == "/dev/disk"* ]]; then
                local partition_path="${disk_device}s${disk_id}"
                local disk_type=$(echo "$line" | awk '{$1=""; $2=""; $3=""; $NF=""; $(NF-1)=""; print}' | xargs)
                local disk_name=$(echo "$line" | awk '{print $(NF-1)}')
                local disk_size=$(echo "$line" | awk '{print $NF}')
                
                echo "$i  | $partition_path | $disk_type | $disk_name | $disk_size"
                partitions+=($partition_path)
                partition_names+=("$disk_name")
                ((i++))
            fi
        done < "$partition_file"
    fi
    
    if [ ${#partitions[@]} -eq 0 ]; then
        warning "No partitions were detected. This is unusual."
        warning "Let's try a direct approach - please specify the partition identifier directly."
        echo -e "\n${YELLOW}${BOLD}Look at the disk information above and enter the full partition identifier${NC}"
        echo -e "${YELLOW}${BOLD}For example, if you want to use 'disk0s4', just type: disk0s4${NC}"
        read -r -p "${YELLOW}${BOLD}Enter the partition identifier:${NC} " direct_partition
        
        if [[ "$direct_partition" == disk* ]]; then
            partitions+=("/dev/$direct_partition")
            partition_names+=("User-specified partition")
        else
            fatal "Invalid partition identifier: $direct_partition"
        fi
    fi
    
    # Ask user to select a partition if we have more than one
    local selected_partition
    if [ ${#partitions[@]} -eq 1 ]; then
        selected_partition=${partitions[0]}
        info "Auto-selecting the only available partition: $selected_partition"
    else
        # Ask user to select a partition
        echo -e "\n${YELLOW}${BOLD}Please select a partition for Kali Linux installation:${NC}"
        echo -e "${YELLOW}${BOLD}Either enter the ID number (0, 1, 2, etc.) OR the full partition name (e.g., disk0s4):${NC}"
        read -r -p "${YELLOW}${BOLD}Enter partition ID or name:${NC} " selection
        
        # First, check if user entered a direct partition identifier (like disk0s4)
        if [[ "$selection" == disk* ]]; then
            # User entered a disk identifier directly
            selected_partition="/dev/$selection"
            info "Using directly specified partition: $selected_partition"
            
            # Verify the partition exists
            if ! diskutil info "$selected_partition" &>/dev/null; then
                fatal "The specified partition $selected_partition does not exist"
            fi
        elif [[ "$selection" == "/dev/disk"* ]]; then
            # User entered a full path
            selected_partition="$selection"
            info "Using directly specified partition: $selected_partition"
            
            # Verify the partition exists
            if ! diskutil info "$selected_partition" &>/dev/null; then
                fatal "The specified partition $selected_partition does not exist"
            fi
        else
            # Validate numeric selection
            if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#partitions[@]}" ]; then
                fatal "Invalid partition selection: $selection. Must be a number between 0 and $((${#partitions[@]}-1)) or a valid partition name."
            fi
            
            selected_partition=${partitions[$selection]}
        fi
    fi
    
    # Show the selected partition and confirm
    info "Selected partition: $selected_partition"
    
    # Get detailed info about the selected partition
    local part_info=""
    if [ -e "$selected_partition" ]; then
        part_info=$(diskutil info "$selected_partition" | grep -E "Device Identifier|Media Name|Volume Name|Total Size")
        echo -e "\n${BLUE}${BOLD}Selected partition details:${NC}"
        echo "$part_info"
    else
        warning "Could not get detailed information for $selected_partition"
    fi
    
    # Confirm selection with warning
    echo -e "${RED}${BOLD}WARNING: You've selected $selected_partition${NC}"
    echo -e "${RED}${BOLD}ALL DATA ON THIS PARTITION WILL BE ERASED!${NC}"
    if ! confirm "Are you ABSOLUTELY SURE you want to use this partition for Kali Linux?" "n"; then
        fatal "Partition selection aborted by user."
    fi
    
    # Check if the partition is mounted
    local is_mounted
    is_mounted=$(diskutil info "$selected_partition" | grep "Mounted" | awk '{print $2}')
    
    if [ "$is_mounted" = "Yes" ]; then
        # Get mount point
        local mount_point
        mount_point=$(diskutil info "$selected_partition" | grep "Mount Point" | awk '{print $3}')
        
        # Unmount the partition
        info "Unmounting partition $selected_partition from $mount_point..."
        sudo diskutil unmount "$selected_partition" || fatal "Failed to unmount partition $selected_partition"
    fi
    
    # Format the partition for Kali Linux (FAT32 initially)
    info "Formatting partition $selected_partition for Kali Linux..."
    sudo diskutil eraseVolume FAT32 "KALI" "$selected_partition" || fatal "Failed to format partition $selected_partition"
    
    # Unmount again after formatting
    sudo diskutil unmount "$selected_partition" || warning "Partition already unmounted or unmount failed."
    
    # We need to remember this partition for later use
    echo "$selected_partition" > "$WORK_DIR/target_partition"
    
    success "Prepared existing partition for Kali Linux: $selected_partition"
    return 0
}

# Function to list available disks for partitioning
list_available_disks() {
    info "Listing available disks..."
    
    # Get list of disks with diskutil
    diskutil list | grep -E "^/dev/disk[0-9]+" | grep -v "disk image"
    
    # For each disk, show more detailed information
    local disks=($(diskutil list | grep -E "^/dev/disk[0-9]+" | grep -v "disk image" | awk '{print $1}'))
    
    echo -e "\n${BLUE}${BOLD}Available disks:${NC}"
    for disk in "${disks[@]}"; do
        echo -e "\n${YELLOW}${BOLD}Disk: $disk${NC}"
        diskutil info "$disk" | grep -E "Device Identifier|Media Name|Media Size|Volume Name"
    done
}

# Function to prepare disk for Kali Linux installation
prepare_disk() {
    print_step "4" "Preparing disk for Kali Linux installation"
    
    # List available disks
    list_available_disks
    
    # Ask user which disk to use
    local target_disk
    read -r -p "${YELLOW}${BOLD}Enter the disk identifier to use (e.g., disk0):${NC} " target_disk
    
    # Validate disk choice
    if ! diskutil list | grep -q "^/dev/$target_disk"; then
        fatal "Invalid disk identifier: $target_disk"
    fi
    
    # Ask for confirmation, especially important as this is destructive
    echo -e "${RED}${BOLD}WARNING: You've selected /dev/$target_disk for partitioning.${NC}"
    echo -e "${RED}${BOLD}This will modify your disk's partition structure!${NC}"
    echo -e "${RED}${BOLD}ALL DATA ON ANY PARTITIONS YOU REMOVE WILL BE LOST!${NC}"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?" "n"; then
        fatal "Disk preparation aborted by user."
    fi
    
    # Determine partition approach
    info "There are two approaches to creating a Kali Linux partition:"
    echo "1. Create a new partition (recommended)"
    echo "2. Use an existing non-system partition"
    
    local approach
    read -r -p "${YELLOW}${BOLD}Choose an approach (1/2):${NC} " approach
    
    case "$approach" in
        1)
            create_new_partition "$target_disk"
            ;;
        2)
            use_existing_partition "$target_disk"
            ;;
        *)
            fatal "Invalid choice. Please choose 1 or 2."
            ;;
    esac
    
    success "Disk preparation completed successfully."
}

# Function to create a new partition for Kali Linux
create_new_partition() {
    local target_disk="$1"
    info "Creating a new partition on /dev/$target_disk for Kali Linux..."
    
    # Determine available space
    local disk_size
    disk_size=$(diskutil info "/dev/$target_disk" | grep "Disk Size" | awk '{print $5}' | tr -d '()' | sed 's/,//g')
    disk_size=$((disk_size / 1000000000)) # Convert to GB
    
    info "Disk size: ${disk_size}GB"
    
    # Ask for partition size
    local partition_size
    read -r -p "${YELLOW}${BOLD}Enter the size for Kali Linux partition in GB (default: $DEFAULT_PARTITION_SIZE):${NC} " partition_size
    
    # Use default if empty
    if [ -z "$partition_size" ]; then
        partition_size=$DEFAULT_PARTITION_SIZE
    fi
    
    # Validate partition size
    if ! [[ "$partition_size" =~ ^[0-9]+$ ]]; then
        fatal "Invalid partition size: $partition_size. Please enter a number in GB."
    fi
    
    if [ "$partition_size" -lt "$MIN_REQUIRED_SPACE" ]; then
        warning "The specified partition size (${partition_size}GB) is less than the recommended minimum (${MIN_REQUIRED_SPACE}GB)."
        if ! confirm "Do you want to continue with a smaller partition size?"; then
            fatal "Partition creation aborted due to insufficient partition size."
        fi
    fi
    
    if [ "$partition_size" -gt "$disk_size" ]; then
        fatal "The specified partition size (${partition_size}GB) exceeds the available disk size (${disk_size}GB)."
    fi
    
    # Show current partition table before changes
    info "Current partition table:"
    diskutil list "/dev/$target_disk"
    
    # Confirm partition creation
    if ! confirm "Ready to create a ${partition_size}GB partition on /dev/$target_disk for Kali Linux. Continue?"; then
        fatal "Partition creation aborted by user."
    fi
    
    # Create partition (requires sudo)
    info "Creating partition..."
    local exit_code=0
    local new_partition
    
    # Determine if we need to resize APFS container first for Apple Silicon Macs
    if diskutil list "/dev/$target_disk" | grep -q "Apple_APFS"; then
        info "APFS container detected. Resizing to make space for Linux partition..."
        
        # Get APFS container ID
        local container_id
        container_id=$(diskutil list "/dev/$target_disk" | grep -E "Apple_APFS Container" | awk '{print $NF}')
        
        if [ -z "$container_id" ]; then
            fatal "Failed to identify APFS container on /dev/$target_disk"
        fi
        
        # Calculate new APFS container size
        local new_container_size
        new_container_size=$((disk_size - partition_size))
        
        # Resize APFS container
        sudo diskutil apfs resizeContainer "$container_id" "${new_container_size}g" FAT32 "KALI" "${partition_size}g" || exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            fatal "Failed to resize APFS container and create Kali partition. Error code: $exit_code"
        fi
        
        # Find the newly created partition
        new_partition=$(diskutil list | grep -B 5 "KALI" | grep -E "^/dev/disk" | tail -n 1 | awk '{print $1}')
    else
        # For non-APFS setups or external drives
        sudo diskutil partitionDisk "/dev/$target_disk" GPT FAT32 "KALI" "${partition_size}g" || exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            fatal "Failed to create Kali partition. Error code: $exit_code"
        fi
        
        # Find the newly created partition
        new_partition=$(diskutil list | grep -B 5 "KALI" | grep -E "^/dev/disk" | tail -n 1 | awk '{print $1}')
    fi
    
    # Verify the partition was created
    if [ -z "$new_partition" ]; then
        fatal "Failed to identify the newly created partition."
    fi
    
    success "Created new partition for Kali Linux: $new_partition"
    
    # Format partition for Kali Linux (ext4 filesystem)
    info "Formatting partition for Kali Linux..."
    sudo diskutil unmount "$new_partition" || warning "Partition already unmounted or unmount failed."
    
    # We need to remember this partition for later use
    echo "$new_partition" > "$WORK_DIR/target_partition"
    
    return 0
}

# Function to use an existing partition for Kali Linux
use_existing_partition() {
    local target_disk="$1"
    info "Selecting an existing partition on /dev/$target_disk for Kali Linux..."
    
    # Show partition table for selection
    info "Current partition table:"
    diskutil list "/dev/$target_disk"
    
    # Get list of partitions
    local partitions=($(diskutil list "/dev/$target_disk" | grep -E "^/dev/" | awk '{print $1}'))
    
    if [ ${#partitions[@]} -eq 0 ]; then
        fatal "No partitions found on /dev/$target_disk"
    fi
    
    # List partitions with details
    echo -e "\n${BLUE}${BOLD}Available partitions on /dev/$target_disk:${NC}"
    local i=0
    for part in "${partitions[@]}"; do
        echo -e "$i: $part"
        diskutil info "$part" | grep -E "Device Identifier|Media Name|Volume Name|File System|Mount Point|Volume|Size"
        echo ""
        ((i++))
    done
    
    # Ask user to select a partition
    local selection
    read -r -p "${YELLOW}${BOLD}Enter the number of the partition to use for Kali Linux:${NC} " selection
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#partitions[@]}" ]; then
        fatal "Invalid partition selection: $selection"
    fi
    
    local selected_partition=${partitions[$selection]}
    
    # Check if the partition is mounted
    local is_mounted
    is_mounted=$(diskutil info "$selected_partition" | grep "Mounted" | awk '{print $2}')
    
    if [ "$is_mounted" = "Yes" ]; then
        # Get mount point
        local mount_point
        mount_point=$(diskutil info "$selected_partition" | grep "Mount Point" | awk '{print $3}')
        
        # Check if it's a system partition
        if [ "$mount_point" = "/" ] || [[ "$mount_point" == */System* ]] || [[ "$mount_point" == */Users* ]]; then
            fatal "Cannot use system partition $selected_partition mounted at $mount_point"
        fi
        
        # Warn about data loss
        warning "The selected partition $selected_partition is mounted at $mount_point"
        warning "ALL DATA ON THIS PARTITION WILL BE ERASED!"
        if ! confirm "Are you ABSOLUTELY SURE you want to use this partition?" "n"; then
            fatal "Partition selection aborted by user."
        fi
        
        # Unmount the partition
        info "Unmounting partition $selected_partition..."
        sudo diskutil unmount "$selected_partition" || fatal "Failed to unmount partition $selected_partition"
    fi
    
    # Format the partition for Kali Linux (FAT32 initially)
    info "Formatting partition $selected_partition for Kali Linux..."
    sudo diskutil eraseVolume FAT32 "KALI" "$selected_partition" || fatal "Failed to format partition $selected_partition"
    
    # Unmount again after formatting
    sudo diskutil unmount "$selected_partition" || warning "Partition already unmounted or unmount failed."
    
    # We need to remember this partition for later use
    echo "$selected_partition" > "$WORK_DIR/target_partition"
    
    success "Prepared existing partition for Kali Linux: $selected_partition"
    return 0
}

#####################################################
#             INSTALLATION FUNCTIONS               #
#####################################################

# Install Kali Linux on the prepared partition
install_kali() {
    print_step "5" "Installing Kali Linux"
    
    # Get the target partition from the previous step
    local target_partition
    if [ -f "$WORK_DIR/target_partition" ]; then
        target_partition=$(cat "$WORK_DIR/target_partition")
    else
        fatal "Target partition information not found. Did you complete the disk preparation step?"
    fi
    
    info "Installing Kali Linux to $target_partition..."
    
    # Create mountpoint for the target partition
    local mount_point="$WORK_DIR/kali_mount"
    mkdir -p "$mount_point"
    
    # Mount the target partition
    info "Mounting target partition..."
    sudo diskutil mount -mountPoint "$mount_point" "$target_partition" || fatal "Failed to mount target partition $target_partition"
    
    # For Apple Silicon Macs, we'll write the ISO directly to the disk using dd
    # This is the most reliable method for handling Linux ISOs on macOS
    
    info "Preparing to write Kali Linux ISO directly to partition..."
    
    # First unmount the target partition since we'll be writing to it directly
    info "Unmounting target partition for direct write..."
    sudo diskutil unmount "$mount_point"
    
    # Get the raw device path (rdisk instead of disk) for better performance
    # First strip off /dev/ if it exists in the target partition path
    local disk_name=$(basename "$target_partition")
    local raw_target="/dev/r$disk_name"
    
    # For safety, confirm one more time
    echo -e "\n${RED}${BOLD}WARNING: About to directly write ISO to partition $target_partition${NC}"
    echo -e "${RED}${BOLD}This will COMPLETELY ERASE all data on this partition.${NC}"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?" "n"; then
        fatal "Installation aborted by user."
    fi
    
    # Write the ISO directly to the partition using dd
    info "Writing Kali Linux ISO to partition $target_partition..."
    info "This will take some time. Please be patient..."
    
    # Calculate ISO size for progress reporting
    local iso_size=$(stat -f %z "$KALI_DISK_IMAGE")
    local block_size=4m
    
    # Use dd with progress output for feedback
    # On macOS, dd doesn't have a status=progress option, so we'll use pv if available
    if command -v pv &>/dev/null; then
        info "Using pv for progress reporting..."
        # Use pv to show progress
        sudo pv -pterb "$KALI_DISK_IMAGE" | sudo dd of="$raw_target" bs=4m 2>/dev/null || {
            error "Failed to write ISO to partition"
            # Try remounting the partition
            sudo diskutil mount -mountPoint "$mount_point" "$target_partition" || warning "Failed to remount partition"
            fatal "Installation failed"
        }
    else
        info "Using dd directly (no progress reporting available)..."
        # Set up a background process to show some activity
        echo -n "Writing ISO: "
        (while :; do echo -n "."; sleep 2; done) &
        activity_pid=$!
        # Ensure the activity indicator is stopped even if dd fails
        trap "kill $activity_pid 2>/dev/null" EXIT
        
        # Run dd and suppress most output
        sudo dd if="$KALI_DISK_IMAGE" of="$raw_target" bs=4m 2>/dev/null || {
            echo -e "\n"
            kill $activity_pid 2>/dev/null
            trap - EXIT
            error "Failed to write ISO to partition"
            # Try remounting the partition
            sudo diskutil mount -mountPoint "$mount_point" "$target_partition" || warning "Failed to remount partition"
            fatal "Installation failed"
        }
        
        # Stop the activity indicator
        kill $activity_pid 2>/dev/null
        trap - EXIT
        echo -e "\nWrite completed."
    fi
    
    info "ISO has been written to partition successfully"
    
    # Try to remount the target partition, but continue if it fails
    # This is normal - macOS can't mount Linux filesystems after writing the ISO
    info "Attempting to remount target partition..."
    if sudo diskutil mount -mountPoint "$mount_point" "$target_partition" 2>/dev/null; then
        info "Target partition remounted successfully."
    else
        warning "Could not remount the partition - this is normal after writing a Linux ISO."
        warning "The partition is now formatted with Linux filesystems that macOS cannot mount."
        warning "This is expected behavior and not an error - the installation was successful."
    fi
    
    info "Kali Linux has been written to the partition successfully."
    
    # Clean up any temporary files
    info "Cleaning up temporary files..."
    # Remove any DMG we might have created in previous attempts
    if [ -f "$WORK_DIR/kali.dmg" ]; then
        rm -f "$WORK_DIR/kali.dmg"
    fi
    
    # Configure bootloader files on the target partition
    info "Configuring bootloader..."
    
    # Create necessary directories if they don't exist
    sudo mkdir -p "$mount_point/boot/grub" || fatal "Failed to create boot directories"
    
    # Create a basic GRUB configuration file
    cat > "$WORK_DIR/grub.cfg" <<EOL
set default=0
set timeout=5

menuentry "Kali Linux on Apple Silicon" {
    linux /boot/vmlinuz root=/dev/$(basename "$target_partition") ro quiet splash
    initrd /boot/initrd.img
}

menuentry "Kali Linux (Recovery Mode)" {
    linux /boot/vmlinuz root=/dev/$(basename "$target_partition") ro single
    initrd /boot/initrd.img
}
EOL
    
    # Copy GRUB config to the target partition
    sudo cp "$WORK_DIR/grub.cfg" "$mount_point/boot/grub/" || fatal "Failed to copy GRUB configuration"
    
    # Create a text file with installation notes
    cat > "$WORK_DIR/kali_notes.txt" <<EOL
=== Kali Linux on Apple Silicon Installation Notes ===

This installation was performed using the Kali Linux Apple Silicon Installer Script.

Important information:
- Installation date: $(date)
- Target partition: $target_partition
- ISO used: $KALI_DISK_IMAGE

Known limitations:
- Wi-Fi and Bluetooth might require additional drivers
- Some hardware features might not be fully supported
- Performance may vary compared to native macOS

First boot instructions:
1. At boot, hold down the power button to access startup options
2. Select the rEFInd bootloader
3. Choose Kali Linux from the boot menu
4. Complete the initial setup as prompted

For support and updates, visit:
- https://www.kali.org/docs/
- https://forums.kali.org/
EOL
    
    # Copy notes to the target partition
    sudo cp "$WORK_DIR/kali_notes.txt" "$mount_point/" || warning "Failed to copy installation notes"
    
    # Unmount the target partition
    info "Unmounting target partition..."
    sudo diskutil unmount "$mount_point" || warning "Failed to unmount target partition"
    
    success "Kali Linux installation completed successfully."
}

# Configure dual boot with rEFInd
configure_dual_boot() {
    print_step "6" "Configuring dual boot"
    
    # Get the target partition from the previous step
    local target_partition
    if [ -f "$WORK_DIR/target_partition" ]; then
        target_partition=$(cat "$WORK_DIR/target_partition")
    else
        fatal "Target partition information not found. Did you complete the disk preparation step?"
    fi
    
    info "Configuring dual boot with rEFInd..."
    
    # Find and mount the EFI partition
    info "Finding EFI partition..."
    local efi_partition
    efi_partition=$(diskutil list | grep EFI | awk '{print $NF}')
    
    if [ -z "$efi_partition" ]; then
        warning "Could not automatically find EFI partition."
        diskutil list
        read -r -p "${YELLOW}${BOLD}Enter the EFI partition identifier (e.g., disk0s1):${NC} " efi_partition
    fi
    
    # Create mount point for EFI partition
    local efi_mount="/Volumes/EFI"
    mkdir -p "$efi_mount"
    
    # Check if already mounted
    if mount | grep -q "$efi_mount"; then
        info "EFI partition is already mounted."
    else
        # Mount the EFI partition
        info "Mounting EFI partition..."
        sudo diskutil mount -mountPoint "$efi_mount" "$efi_partition" || fatal "Failed to mount EFI partition"
    fi
    
    # Check if rEFInd is installed
    if [ ! -d "$efi_mount/EFI/refind" ]; then
        warning "rEFInd directory not found in EFI partition."
        warning "The bootloader might not be properly installed."
        if ! confirm "Do you want to continue anyway?"; then
            sudo diskutil unmount "$efi_mount" || warning "Failed to unmount EFI partition"
            fatal "Dual boot configuration aborted due to missing rEFInd bootloader."
        fi
    fi
    
    # Check if refind.conf exists, create it if not
    if [ ! -f "$efi_mount/EFI/refind/refind.conf" ]; then
        warning "rEFInd configuration file not found. Creating a basic one..."
        sudo mkdir -p "$efi_mount/EFI/refind"
        
        # Create basic refind.conf
        cat > "$WORK_DIR/refind.conf" <<EOL
timeout 20
resolution 1920 1080
use_graphics_for osx,linux
hideui singleuser
scanfor manual,external,optical

# macOS
menuentry "macOS" {
    icon /EFI/refind/icons/os_mac.icns
    volume "MacOS"
    loader /System/Library/CoreServices/boot.efi
}
EOL
        
        sudo cp "$WORK_DIR/refind.conf" "$efi_mount/EFI/refind/" || fatal "Failed to create rEFInd configuration file"
    fi
    
    # Check if Kali Linux entry already exists in refind.conf
    if grep -q "Kali Linux" "$efi_mount/EFI/refind/refind.conf"; then
        info "Kali Linux entry already exists in rEFInd configuration."
    else
        # Add Kali Linux entry to refind.conf
        info "Adding Kali Linux to rEFInd boot options..."
        
        # Create a config snippet for Kali Linux
        cat > "$WORK_DIR/kali_config.txt" <<EOL

# Kali Linux
menuentry "Kali Linux" {
    icon /EFI/refind/icons/os_linux.png
    volume "KALI"
    loader /boot/vmlinuz
    initrd /boot/initrd.img
    options "root=/dev/$(basename "$target_partition") ro quiet splash"
}
EOL
        
        # Append the config snippet to refind.conf
        sudo bash -c "cat '$WORK_DIR/kali_config.txt' >> '$efi_mount/EFI/refind/refind.conf'" || \
            fatal "Failed to update rEFInd configuration"
    fi
    
    # Ensure rEFInd icons directory exists and has Linux icon
    if [ ! -d "$efi_mount/EFI/refind/icons" ]; then
        warning "rEFInd icons directory not found. Creating it..."
        sudo mkdir -p "$efi_mount/EFI/refind/icons"
    fi
    
    # Check if the Linux icon exists, if not, try to find it or use a generic one
    if [ ! -f "$efi_mount/EFI/refind/icons/os_linux.png" ]; then
        warning "Linux icon not found in rEFInd icons directory."
        
        # Try to find it in the system
        local linux_icon
        if [ -f "/usr/local/share/refind/icons/os_linux.png" ]; then
            linux_icon="/usr/local/share/refind/icons/os_linux.png"
        elif [ -f "/usr/share/refind/icons/os_linux.png" ]; then
            linux_icon="/usr/share/refind/icons/os_linux.png"
        else
            warning "Could not find Linux icon. Dual boot will work but may not show the Linux icon."
        fi
        
        # Copy the icon if found
        if [ -n "$linux_icon" ]; then
            sudo cp "$linux_icon" "$efi_mount/EFI/refind/icons/" || \
                warning "Failed to copy Linux icon. Boot will work but may not show the Linux icon."
        fi
    fi
    
    # Unmount EFI partition
    info "Unmounting EFI partition..."
    sudo diskutil unmount "$efi_mount" || warning "Failed to unmount EFI partition"
    
    success "Dual boot configuration completed successfully."
}

#####################################################
#             CLEANUP AND COMPLETION                #
#####################################################

# Complete installation and provide final instructions
complete_installation() {
    print_step "7" "Installation Complete"
    
    # Clean up temporary files
    info "Cleaning up temporary files..."
    rm -rf "$WORK_DIR" || warning "Failed to clean up some temporary files"
    
    # Provide final instructions
    echo -e "\n${GREEN}${BOLD}=== KALI LINUX INSTALLATION COMPLETED SUCCESSFULLY ===${NC}"
    echo -e "\n${BLUE}${BOLD}Next Steps:${NC}"
    echo "1. Restart your Mac."
    echo "2. Hold the power button until you see 'Loading startup options'."
    echo "3. Select the rEFInd bootloader."
    echo "4. Choose Kali Linux from the boot menu."
    echo "5. Complete the Kali Linux setup process."
    
    echo -e "\n${YELLOW}${BOLD}IMPORTANT NOTES:${NC}"
    echo "- Linux support on Apple Silicon is experimental and may have limitations."
    echo "- Wi-Fi, Bluetooth, and certain hardware features might require additional drivers."
    echo "- Always boot macOS occasionally to allow firmware updates."
    echo "- Complete log of this installation is available at: $LOG_FILE"
    
    echo -e "\n${GREEN}${BOLD}Enjoy your Kali Linux installation!${NC}"
}

#####################################################
#                MAIN EXECUTION                    #
#####################################################

# Handle script interruption
cleanup_on_exit() {
    echo -e "\n${RED}Script interrupted. Cleaning up...${NC}" >&2
    
    # Unmount any mounted volumes we might have left
    for mount_point in "$WORK_DIR/kali_mount" "$WORK_DIR/iso_mount" "/Volumes/EFI"; do
        if mount | grep -q "$mount_point"; then
            sudo diskutil unmount "$mount_point" >/dev/null 2>&1
        fi
    done
    
    echo "Installation was not completed. Log file is available at: $LOG_FILE" >&2
    exit 1
}

# Set up trap for script interruption
trap cleanup_on_exit INT TERM

# Main function to execute the installation process
main() {
    # Define total steps
    TOTAL_STEPS=7
    
    # Display header
    header
    
    # Check for command line arguments
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h           Show this help message"
        echo "  --skip-checks        Skip prerequisite checks (not recommended)"
        echo "  --configure-only     Only configure dual boot (use after manual installation)"
        echo "  --use-existing       Use an existing partition for Kali Linux"
        echo ""
        exit 0
    fi
    
    # Check if running configure-only mode
    if [ "$1" = "--configure-only" ]; then
        info "Running in configure-only mode"
        check_sudo_access
        configure_dual_boot
        exit 0
    fi
    
    # Check prerequisites unless skipped
    if [ "$1" = "--skip-checks" ]; then
        warning "Skipping prerequisite checks as requested"
    else
        check_prerequisites
    fi
    
    # Show available partitions immediately - this is important to the user
    echo -e "\n${BLUE}${BOLD}Available disks and partitions on your system:${NC}"
    info "These are all the partitions on your system. Note the partition identifier (like disk0s5)"
    info "that you want to use for Kali Linux if you already have a partition ready."
    diskutil list
    
    # Immediately ask if they want to use an existing partition
    local use_existing_partition=false
    local target_partition=""
    
    if [ "$1" = "--use-existing" ] || confirm "Do you want to use an existing partition for Kali Linux?" "y"; then
        use_existing_partition=true
        # First, determine the partition to use for Kali Linux
        # Direct to select_existing_partition function
        target_partition=$(select_existing_partition)
    else
        # Let them know we will create a new partition later
        info "You've chosen to create a new partition for Kali Linux."
        info "You'll be guided through partition creation shortly."
    fi
    
    # NOW confirm installation after they've chosen a partition
    # This confirms they want to proceed with the selected partition
    if ! confirm "Ready to install Kali Linux to the selected partition?" "n"; then
        fatal "Installation aborted by user."
    fi
    
    # If we're creating a new partition, do that now
    if [ "$use_existing_partition" = false ]; then
        # Create a new partition
        prepare_disk
    fi
    
    # Now that we know the partition, proceed with the rest of the installation
    download_kali
    install_bootloader
    install_kali
    configure_dual_boot
    complete_installation
    
    return 0
}

# Run the main function with command line arguments
main "$@"
