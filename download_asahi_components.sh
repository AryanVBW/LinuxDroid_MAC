#!/bin/sh
# Script to download all Asahi Linux components without installing
# Captures the full installation process for analysis

# Create a directory to store all downloaded files
mkdir -p asahi_components
cd asahi_components

echo "==== Asahi Linux Component Downloader ===="
echo "This script will download all components used by the Asahi Linux installer"
echo "but will NOT perform the actual installation."
echo ""

# First get the latest version
echo "1. Checking latest installer version..."
VERSION_FLAG="https://cdn.asahilinux.org/installer/latest"
INSTALLER_BASE="https://cdn.asahilinux.org/installer"
INSTALLER_DATA="https://github.com/AsahiLinux/asahi-installer/raw/prod/data/installer_data.json"
INSTALLER_DATA_ALT="https://alx.sh/installer_data.json"
REPO_BASE="https://cdn.asahilinux.org"

PKG_VER=$(curl --no-progress-meter -L "$VERSION_FLAG")
echo "   Latest version: $PKG_VER"

# Download the installer package
echo "2. Downloading installer package..."
PKG="installer-$PKG_VER.tar.gz"
curl -L -o "$PKG" "$INSTALLER_BASE/$PKG"
echo "   Downloaded: $PKG"

# Download the installer data JSON
echo "3. Downloading installer data..."
if ! curl -L -o "installer_data.json" "$INSTALLER_DATA"; then
    echo "   Error downloading from GitHub, trying alternative source..."
    curl -L -o "installer_data.json" "$INSTALLER_DATA_ALT"
fi
echo "   Downloaded: installer_data.json"

# Extract the installer package
echo "4. Extracting installer package..."
mkdir extracted
tar xf "$PKG" -C extracted
echo "   Extracted to: ./extracted/"

# Parse the installer data to find OS images
echo "5. Parsing installer data for OS images..."
if [ -f "installer_data.json" ]; then
    echo "   Available OS images (from installer_data.json):"
    grep -o '"name": "[^"]*"' installer_data.json | cut -d'"' -f4
    
    # This is a simplified approach - a real parser would be more complex
    echo "   Note: Not downloading OS images as they are large and selected during installation"
fi

# List all downloaded/extracted files
echo ""
echo "6. All downloaded components:"
echo "   -------------------------"
echo "   Installer package: $PKG"
echo "   Installer data: installer_data.json"
echo ""
echo "   Extracted files:"
find extracted -type f | sort

echo ""
echo "==== Download Complete ===="
echo "All Asahi Linux components have been downloaded to: $(pwd)"
echo "You can examine these files to understand how the installer works"
echo ""
echo "To view the main installer script:"
echo "cat extracted/install.sh"
