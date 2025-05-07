#!/bin/sh
# Modified version of the Asahi Linux installer to debug downloads
# This will download files but not proceed with installation

# Set to display all commands being executed
set -x

# Create directory for downloads
mkdir -p asahi_downloads
cd asahi_downloads

# Begin bootstrap process (copied from original installer)
INSTALLER_BASE="https://alx.sh"
PKG="installer.tar.gz"
INSTALLER_DATA="https://cdn.asahilinux.org/installer_data.json"
INSTALLER_DATA_ALT="https://alx.sh/installer_data.json"

echo "==== DEBUG: Asahi Linux Installer Download Capture ===="
echo "Downloading installer files to: $(pwd)"

echo "DEBUG: Downloading installer package..."
# Use -v for verbose output to see exactly what's happening
curl -v -L -o "$PKG" "$INSTALLER_BASE/$PKG" || echo "Failed to download $PKG"

echo "DEBUG: Downloading installer data..."
if ! curl -v -L -o "installer_data.json" "$INSTALLER_DATA"; then
    echo "DEBUG: Trying alternative source for installer data..."
    curl -v -L -o "installer_data_alt.json" "$INSTALLER_DATA_ALT" || echo "Failed to download installer data"
fi

# Try to extract the package if download was successful
if [ -f "$PKG" ]; then
    echo "DEBUG: Extracting $PKG to see contents..."
    tar xvf "$PKG" || echo "Failed to extract $PKG"
    
    # List extracted files
    echo "DEBUG: Files extracted:"
    ls -la
    
    # If install.sh exists, view it to see what it does
    if [ -f "install.sh" ]; then
        echo "DEBUG: Contents of install.sh (first 50 lines):"
        head -n 50 install.sh
    fi
fi

# Display any downloaded JSON data
if [ -f "installer_data.json" ]; then
    echo "DEBUG: Contents of installer_data.json:"
    cat installer_data.json
elif [ -f "installer_data_alt.json" ]; then
    echo "DEBUG: Contents of installer_data_alt.json:"
    cat installer_data_alt.json
fi

echo "==== DEBUG COMPLETE ===="
echo "All downloaded files are in: $(pwd)"
echo "IMPORTANT: This was just a download debug - no installation was performed"
