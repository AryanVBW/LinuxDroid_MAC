# Kali Linux Recovery Instructions for Apple Silicon Macs

This guide provides instructions for recovering your Mac if you encounter boot issues after installing Kali Linux.

## If You're Stuck in a Boot Loop or Can't Boot to macOS

1. **Force shutdown your Mac**:
   - Press and hold the power button until your Mac completely turns off.

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

## For Future Reference: Safely Uninstalling Kali Linux

If you want to remove Kali Linux:

1. Boot into macOS
2. Open Terminal
3. Run: `diskutil list` to identify the Kali partition
4. Run: `sudo diskutil eraseDisk APFS "EMPTY" /dev/diskXsY` 
   (replace diskXsY with your Kali partition, e.g., disk0s4)
5. You can then use Disk Utility to merge this empty space back with your macOS partition

## If You Need to Restore the Mac Completely

In extreme cases, you can restore your Mac to factory settings:

1. Boot into Recovery Mode (hold power button until "Loading startup options" appears)
2. Select "Options"
3. Choose "Erase All Content and Settings"
4. Follow the prompts to completely restore your Mac

## Support Resources

- Apple Support: https://support.apple.com
- Kali Linux Documentation: https://www.kali.org/docs/
- Apple Silicon Recovery Mode Guide: https://support.apple.com/guide/mac-help/macos-recovery-a-mac-apple-silicon-mchl82829c17/mac
