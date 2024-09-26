#!/bin/bash

# Install required packages
sudo apt update
sudo apt install -y tpm2-tools tss2 dracut libcurl4 libjson-c5 libtss2-fapi1 libtss2-tcti-cmd0 libtss2-tcti-device0 libtss2-tcti-mssim0 libtss2-tcti-swtpm0

# Download dracut version 059
wget https://github.com/dracutdevs/dracut/archive/refs/tags/059.tar.gz

# Extract the downloaded tarball
tar -xvzf 059.tar.gz
cp -r ./dracut-059/modules.d/01systemd-sysusers /usr/lib/dracut/modules.d/
cp -r ./dracut-059/modules.d/01systemd-udevd /usr/lib/dracut/modules.d/
cp -r ./dracut-059/modules.d/91tpm2-tss /usr/lib/dracut/modules.d/
# Optionally remove the tarball after extraction
#rm 059.tar.gz

# Display block devices and filter LUKS encrypted locations
echo "Finding LUKS partitions..."
LUKS_DEVICE=$(lsblk -o NAME,TYPE,FSTYPE | grep 'crypto_LUKS' | awk '{print $1}' | sed 's/[^a-zA-Z0-9]//g')

# Clean up the device name by adding the /dev/ prefix
LUKS_DEVICE="/dev/$LUKS_DEVICE"

if [ -z "$LUKS_DEVICE" ]; then
    echo "No LUKS encrypted partitions found."
    exit 1
else
    echo "LUKS encrypted partition found: $LUKS_DEVICE"
fi

# Use the found LUKS device with systemd-cryptenroll
echo "Enrolling LUKS device with TPM2..."
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 "$LUKS_DEVICE"

# Check if /etc/dracut.conf.d directory exists
if [ ! -d "/etc/dracut.conf.d" ]; then
    echo "Creating /etc/dracut.conf.d directory..."
    sudo mkdir -p /etc/dracut.conf.d
fi

# Create or append the configuration to /etc/dracut.conf.d/tpm2-tss.conf
DRACUT_CONF="/etc/dracut.conf.d/tpm2-tss.conf"
DRACUT_STRING='add_dracutmodules+=" tpm2-tss crypt "'

# Check if the line already exists, and only append if it doesn't
if ! grep -q "$DRACUT_STRING" "$DRACUT_CONF"; then
    echo "$DRACUT_STRING" | sudo tee -a "$DRACUT_CONF" > /dev/null
    echo "Added dracut configuration to $DRACUT_CONF"
else
    echo "Dracut configuration already present in $DRACUT_CONF, no changes made."
fi

# Modify /etc/default/grub only if GRUB_CMDLINE_LINUX is still empty
GRUB_FILE="/etc/default/grub"
GRUB_CMD="rd.auto rd.luks=1"

if grep -q '^GRUB_CMDLINE_LINUX=""' "$GRUB_FILE"; then
    # If GRUB_CMDLINE_LINUX is empty, add the new options
    sudo sed -i 's|^GRUB_CMDLINE_LINUX=""|GRUB_CMDLINE_LINUX="rd.auto rd.luks=1"|' "$GRUB_FILE"
    echo "GRUB_CMDLINE_LINUX updated with: $GRUB_CMD"
else
    echo "GRUB_CMDLINE_LINUX is not empty, no changes made."
fi

# Update grub to apply changes
#sudo update-grub

# Append tpm2-device parameters to /etc/crypttab
CRYPTTAB_FILE="/etc/crypttab"
TPM_OPTIONS="tpm2-device=auto,luks,discard"

# Check if the file exists
if [ -f "$CRYPTTAB_FILE" ]; then
    # Remove 'luks' from each line and then append the new options
    sudo sed -i "s| luks| |g; s|\(.*\)|\1 $TPM_OPTIONS|" "$CRYPTTAB_FILE"
    echo "Added '$TPM_OPTIONS' to each line in $CRYPTTAB_FILE, removed duplicate 'luks'."
else
    echo "$CRYPTTAB_FILE does not exist."
fi

dracut -f
update-grub
dracut -f

echo "Installation, extraction, LUKS check, TPM enrollment, dracut configuration, GRUB update, and crypttab modification complete."
