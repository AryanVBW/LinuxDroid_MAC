# Kali Linux Troubleshooting Guide for Apple Silicon Macs

This comprehensive guide covers recovery and troubleshooting for various issues you might encounter when installing or booting Kali Linux on Apple Silicon Macs.

## Table of Contents
1. [Boot Loop/Can't Boot macOS](#if-youre-stuck-in-a-boot-loop-or-cant-boot-to-macos)
2. [No Kali Linux Boot Option](#if-kali-linux-doesnt-appear-in-boot-options)
3. [Bootloader Errors](#bootloader-errors)
4. [Installation Errors](#installation-errors)
5. [Wi-Fi/Bluetooth Issues](#hardware-issues)
6. [Display Problems](#display-problems)
7. [Keyboard/Trackpad Issues](#keyboard-and-trackpad-issues)
8. [Partitioning Errors](#partitioning-errors)
9. [System Freezes](#system-freezes)
10. [Uninstalling Kali Linux](#safely-uninstalling-kali-linux)
11. [Complete System Restore](#complete-system-restore)
12. [Support Resources](#support-resources)

## If You're Stuck in a Boot Loop or Can't Boot to macOS

1. **Force shutdown your Mac**:
   - Press and hold the power button until your Mac completely turns off

2. **Boot into Recovery Mode**:
   - Press and hold the power button until you see "Loading startup options"
   - When the startup options appear, select "Options" to enter Recovery Mode

3. **Reset Boot Options Using Startup Security Utility**:
   - In Recovery Mode, select "Utilities" from the menu bar
   - Choose "Startup Security Utility"
   - You may need to authenticate with your password
   - Select "Full Security" (or your preferred security level)
   - Make sure "Allow booting from external media" is unchecked if you want to prevent booting from the Kali partition

4. **Use Disk Utility to Change Partition Visibility (if needed)**:
   - In Recovery Mode, open "Disk Utility"
   - Select the Kali Linux partition (likely labeled "KALI")
   - Click "Unmount" if it's mounted
   - You can also choose "Erase" to completely remove Kali Linux
     (use "APFS" as the format if you want to reclaim the space for macOS)

5. **Boot into macOS Directly**:
   - In Recovery Mode, choose "Startup Disk"
   - Select your macOS partition (usually "Macintosh HD")
   - Click "Restart"

## If Kali Linux Doesn't Appear in Boot Options

### Using Recovery Mode to Boot Kali When It's Not Showing as a Startup Disk

1. **Access Recovery Mode**:
   - Turn off your Mac completely
   - Press and hold the power button until "Loading startup options" appears
   - Select "Options" to enter Recovery Mode

2. **Use Terminal to Find and Boot Kali**:
   - In Recovery Mode, select "Utilities" from the top menu
   - Open "Terminal"
   - Run the following commands to identify your Kali partition:
     ```bash
     diskutil list
     ```
   - Look for your Kali partition (usually labeled as Linux or KALI)
   - Once you've identified the disk identifier (e.g., disk0s4), try to directly boot from it:
     ```bash
     # First check if it contains bootable files
     ls -la /dev/disk0s4
     
     # Try to boot directly from this partition
     bless --device /dev/disk0s4 --setBoot
     reboot
     ```

3. **If Direct Boot Doesn't Work, Try Setting Boot Priority**:
   ```bash
   # Try to set boot priority for Kali
   bless --mount /dev/disk0s4 --setBoot
   # Or try with mount point if the disk can be mounted
   diskutil mount /dev/disk0s4
   bless --mount /Volumes/KALI --setBoot
   ```

4. **Manual Boot Option Using nvram**:
   ```bash
   # Find the GUID of your Kali partition
   diskutil info /dev/disk0s4 | grep "Volume UUID"
   
   # Set this as your boot disk using nvram
   sudo nvram boot-volume="GUID_FROM_ABOVE"
   sudo nvram boot-args="-v"
   reboot
   ```

5. **Security Settings Check**:
   - While in Recovery Mode, select "Utilities" from the menu bar
   - Choose "Startup Security Utility"
   - You may need to authenticate with your password
   - Set Security Policy to "Reduced Security"
   - Enable "Allow booting from external media"

6. **Reinstall rEFInd Bootloader**:
   - Boot into macOS
   - Download rEFInd from https://sourceforge.net/projects/refind/
   - Open Terminal
   - Extract rEFInd: `unzip -d ~/refind refind-bin-*.zip`
   - Run the installation script: `cd ~/refind/refind-bin-* && ./refind-install`

7. **Check Partition Format**:
   - In Terminal, run: `diskutil list` 
   - Verify the Kali partition exists and is properly formatted

## Bootloader Errors

### Error: "No bootable device found"

1. **Reset NVRAM/PRAM**:
   - Shut down your Mac
   - Turn it on and immediately press and hold: Option + Command + P + R
   - Release after about 20 seconds (you might hear the startup sound twice)

### Error: "Invalid loader image"

1. **Reinstall Bootloader**:
   - Boot into macOS and reinstall rEFInd
   - Alternatively, try using a different bootloader like systemd-boot

### Error: "Secure Boot Violation"

1. **Adjust Security Settings**:
   - Boot into Recovery Mode
   - Open Startup Security Utility
   - Set Security Policy to "Reduced Security"
   - Check "Allow booting from external media"

## Installation Errors

### Error: "Failed to write ISO to partition"

1. **Check ISO Integrity**:
   - Verify the Kali Linux ISO checksum
   - Download a fresh copy if needed

2. **Check Disk Space**:
   - Ensure your target partition is large enough (at least 20GB recommended)

3. **Try Alternative Installation Method**:
   - Try using `dd` command manually: 
     `sudo dd if=/path/to/kali.iso of=/dev/rdiskXsY bs=4m`

### Error: "Could not mount target partition"

1. **Format Partition First**:
   - Use Disk Utility to format the partition as "MS-DOS (FAT)" before installation
   - Run the installer again

## Hardware Issues

### Wi-Fi/Bluetooth Not Working

1. **Install Drivers**:
   - Many Apple devices require proprietary drivers
   - In Kali, open Terminal and run:
     ```
     sudo apt update
     sudo apt install firmware-misc-nonfree firmware-atheros firmware-realtek
     ```

2. **Use External Adapters**:
   - Consider USB Wi-Fi/Bluetooth adapters known to work with Linux

## Display Problems

### Screen Resolution Issues

1. **Add Kernel Parameters**:
   - Edit /etc/default/grub
   - Add to GRUB_CMDLINE_LINUX: `video=1920x1080`
   - Run: `sudo update-grub`

### Screen Brightness Control Not Working

1. **Install Brightness Control Utilities**:
   ```
   sudo apt install brightnessctl
   ```

## Keyboard and Trackpad Issues

1. **Configure Input Devices**:
   ```
   sudo apt install xserver-xorg-input-libinput
   sudo apt install xserver-xorg-input-synaptics
   ```

2. **Create Custom xorg.conf**:
   - Create/edit /etc/X11/xorg.conf.d/30-touchpad.conf with appropriate settings

## Partitioning Errors

### Error: "Could not unmount disk"

1. **Force Unmount**:
   ```
   sudo diskutil unmountDisk force /dev/diskX
   ```

### Error: "Operation not permitted"

1. **Check SIP Status**:
   - System Integrity Protection might be preventing disk operations
   - Boot to Recovery Mode and run: `csrutil disable`
   - After installation, consider re-enabling: `csrutil enable`

## System Freezes

1. **Update Kernel**:
   - Try using a more recent Linux kernel which might have better Apple Silicon support

2. **Boot Parameters**:
   - Add `acpi=off` to kernel parameters
   - Try `amdgpu.runpm=0` for graphics-related freezes

## Safely Uninstalling Kali Linux

1. Boot into macOS
2. Open Terminal
3. Run: `diskutil list` to identify the Kali partition
4. Run: `sudo diskutil eraseDisk APFS "EMPTY" /dev/diskXsY` 
   (replace diskXsY with your Kali partition, e.g., disk0s4)
5. Reclaim the space using Disk Utility or run:
   `diskutil mergePartitions APFS "Macintosh HD" diskXsY diskXsZ`

## Emergency Boot Recovery

### If You're Stuck in a Boot Loop

1. **Immediate Recovery to macOS**:
   - Force shutdown by holding the power button
   - Boot while holding COMMAND+R to enter Recovery Mode
   - In Recovery, go to Startup Disk
   - Select Macintosh HD (your macOS partition)
   - Click Restart

2. **If That Doesn't Work - Boot to Safe Mode**:
   - Shut down your Mac
   - Press the power button to turn on, then immediately press and hold Shift
   - Release when you see the login screen

3. **Reset SMC (System Management Controller)**:
   - Shut down your Mac
   - Press and hold Control+Option+Shift for 7 seconds
   - While holding those keys, press and hold the power button for another 7 seconds
   - Release all keys, wait 5 seconds, then press power button to turn on

### Fixing Broken Boot Files

1. **From Recovery Mode Terminal**:
   - Boot to Recovery Mode (hold power button until options appear, then select Options)
   - Open Terminal from Utilities menu
   - Run the following commands:

   ```bash
   # Mount the main macOS system volume
   diskutil list
   diskutil mount /dev/diskXsY  # Replace X and Y with your macOS system volume
   
   # Delete Kali boot files if they're interfering with boot
   rm -rf /Volumes/"Macintosh HD"/Library/StartupItems/refind*
   rm -rf /Volumes/"Macintosh HD"/Library/LaunchDaemons/org.refind.*
   
   # Reset boot preferences
   bless --folder /Volumes/"Macintosh HD"/System/Library/CoreServices --bootefi --create-snapshot
   ```

2. **Restore Boot Order and Security**:
   ```bash
   # Check current boot order and security
   bputil -d
   
   # Set to boot macOS first
   sudo bless --setBoot --folder /Volumes/"Macintosh HD"/System/Library/CoreServices
   
   # Reset to default boot security (full security)
   sudo bputil -f
   ```

### Completely Disable Kali Boot Option

1. **Erase the Kali Partition**:
   - In Recovery Mode, open Disk Utility
   - Select the Kali partition
   - Click Erase
   - Format: APFS
   - Name: Whatever you prefer

2. **Remove Boot Records**:
   - In Recovery Mode Terminal:
   ```bash
   # List all volumes to find the EFI partition
   diskutil list
   
   # Mount the EFI partition
   sudo diskutil mount /dev/diskXsY  # Replace with your EFI partition
   
   # Remove rEFInd or other bootloader files
   sudo rm -rf /Volumes/EFI/EFI/refind
   sudo rm -rf /Volumes/EFI/EFI/BOOT/bootaa64.efi
   
   # Update boot cache
   sudo kextcache -system-prelinked-kernel
   sudo kextcache -system-caches
   ```

## Complete System Restore

In extreme cases, you can restore your Mac to factory settings:

1. Boot into Recovery Mode (hold power button until "Loading startup options" appears)
2. Select "Options"
3. Choose "Erase All Content and Settings"
4. Follow the prompts to completely restore your Mac

## Repairing a Broken Kali Linux Installation

If Kali Linux boots but has issues, or if you want to repair rather than remove:

### Option 1: Boot to Kali Recovery Mode

1. During Kali boot, select "Advanced options for Kali GNU/Linux"
2. Select "Recovery Mode"
3. This will boot into a minimal environment where you can repair your system

### Option 2: Chroot from Live USB

1. Boot from a Kali Linux live USB
2. Open Terminal
3. Mount your Kali partition:
   ```bash
   sudo mkdir -p /mnt/kali
   sudo mount /dev/sdXY /mnt/kali  # Replace with your Kali partition
   sudo mount --bind /dev /mnt/kali/dev
   sudo mount --bind /proc /mnt/kali/proc
   sudo mount --bind /sys /mnt/kali/sys
   ```
4. Chroot into your installation:
   ```bash
   sudo chroot /mnt/kali
   ```
5. Now you can run commands to repair your system:
   ```bash
   # Update and fix packages
   apt update
   apt upgrade
   apt install -f
   
   # Rebuild initramfs
   update-initramfs -u -k all
   
   # Update bootloader
   update-grub
   ```

### Option 3: Reinstall Kali Without Losing Data

If Kali's system files are corrupted but you want to preserve user data:

1. Boot from Kali installation media
2. Select "Advanced" installation options
3. When prompted about partitioning, choose "Manual"
4. Set the existing Kali partition to be used as "/" but DO NOT format it
5. Mark your home directory (if on a separate partition) as "/home" without formatting
6. Complete the installation, which will replace system files but preserve /home

## Support Resources

- Apple Support: https://support.apple.com
- Kali Linux Documentation: https://www.kali.org/docs/
- Apple Silicon Recovery Mode Guide: https://support.apple.com/guide/mac-help/macos-recovery-a-mac-apple-silicon-mchl82829c17/mac
- Kali Linux Forums: https://forums.kali.org/
- rEFInd Documentation: https://www.rodsbooks.com/refind/
- Asahi Linux (Linux on Apple Silicon): https://asahilinux.org/
