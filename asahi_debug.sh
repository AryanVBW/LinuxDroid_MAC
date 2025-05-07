#!/bin/sh
# Modified Asahi Linux installer for debugging
# Creates a local copy of all downloaded files

# Create debug directories
mkdir -p asahi_debug/files
cd asahi_debug

# Set up variables
INSTALLER_BASE="https://raw.githubusercontent.com/AsahiLinux/asahi-installer/main/dist"
PKG="installer.tar.gz"
INSTALLER_DATA="https://cdn.asahilinux.org/installer_data.json"
INSTALLER_DATA_ALT="https://alx.sh/installer_data.json"

echo "==== Asahi Linux Installer Debug Mode ===="
echo "All files will be saved to asahi_debug directory"
echo ""

# Download with verbose output
echo "Downloading installer.tar.gz..."
curl -v -L -o "files/$PKG" "$INSTALLER_BASE/$PKG"

echo "Downloading installer_data.json from main source..."
if ! curl -v -L -o "files/installer_data.json" "$INSTALLER_DATA"; then
    echo "Error with main source. Trying alternative source..."
    curl -v -L -o "files/installer_data_alt.json" "$INSTALLER_DATA_ALT"
fi

echo "Extracting installer.tar.gz to examine contents..."
tar xvf "files/$PKG" -C files/

# Parse and display installer_data.json
echo "==== Contents of installer_data.json ===="
if [ -f "files/installer_data.json" ]; then
    cat "files/installer_data.json"
else
    cat "files/installer_data_alt.json"
fi

echo ""
echo "==== Debug Complete ===="
echo "All downloaded files are in $(pwd)/files/"
echo "You can examine them to see what the installer downloads."
echo ""
echo "The installer would normally download OS images from URLs listed in installer_data.json"
