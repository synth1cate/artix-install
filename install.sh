#!/bin/bash -e

# synth1cate's Artix installer
# for now, there is no way to choose any custom setting
# (unless you painstakingly modify this script)

# this script has been adapted for my machine & preferences exclusively,
# if you do try this on your machine for some reason, YMMV

# credits go to Zaechus (on GitHub) for the original Artix install script
# and suconakh (also on GitHub) for some settings that I borrowed
# all I did was to modify the scripts/configs to suit my needs
# and make the transition from Garuda to Artix smoother

# this script is being tested in a VM. after I'm confident it works
# in a VM, I will eventually use the install script on bare-metal

confirm_pass () {
    local pass1="pass1"
    local pass2="pass2"
    until [[ $pass1 == $pass2 && $pass2 ]]; do
        printf "input: enter root pass\n(*): " >&2 && read -rs pass1
        printf "\n" >&2
        printf "input: confirm root pass\n(*): " >&2 && read -rs pass2
        printf "\n" >&2
    done
    echo $pass2
}

# First, load the default QWERTY keymap
echo "info: loading default QWERTY keymap"
sudo loadkeys us

# Check boot mode. If not UEFI, the installer will quit
[[ ! -d /sys/firmware/efi ]] && printf "error: installer is not compatible with UEFI\ninfo: cancelling..." && exit 1


# Dinit is the default and only init system this script will make use of
init = "dinit"
echo "info: chosen init system is $init"
echo "info: this can't be changed unless you painstakingly edit the script"

# Choosing disk - this requires your input, as the disk name
#                 structure differs from computer to computer

while :
do
    sudo fdisk -l
    printf "\ninfo: specify disk used for installation\n      examples: /dev/sda  /dev/vda  /dev/nvme0n1\n(*): " && read mydisk
    [[ -b $mydisk ]] && break
done

efipart="$mydisk"1
rootpart="$mydisk"2
if [[ $mydisk == *"nvme"* ]]; then
    efipart="$mydisk"p1
    rootpart="$mydisk"p2
fi

# Timezone
until [[ -f /usr/share/zoneinfo/$region_city ]]; do
    printf "input: specify your timezone\n       format - Continent/CapitalCity\n       example: Europe/Bucharest\n(*): " && read region_city
done

# Hostname
while :
do
    printf "input: specify hostname\n(*): " && read myhost
    [[ $myhost ]] && break
done

# Configure root password
rootpass=$(confirm_pass)

# Partition management

sudo umount -A --recursive /mnt
sudo umount -A --recursive $mydisk
sudo swapoff -a $mydisk

printf "label: gpt\n,550M,U\n,,L\n" | sudo sfdisk $mydisk
sudo mkfs.fat -F 32 $efipart
sudo mkfs.btrfs $rootpart --force

sudo mount $rootpart /mnt
mount_opts="defaults,noatime,compress=zstd,discard=async,ssd"

sudo btrfs sub create /mnt/@
sudo btrfs sub create /mnt/@home
sudo btrfs sub create /mnt/@root
sudo btrfs sub create /mnt/@srv
sudo btrfs sub create /mnt/@cache
sudo btrfs sub create /mnt/@log
sudo btrfs sub create /mnt/@tmp

sudo umount /mnt

sudo mount -o $mount_opts,subvol=@ $rootpart /mnt
sudo mkdir -p /mnt/{boot/efi,home,root,srv,var/{cache,log,tmp}}
sudo mount -o $mount_opts,subvol=@home $rootpart /mnt/home
sudo mount -o $mount_opts,subvol=@root $rootpart /mnt/root
sudo mount -o $mount_opts,subvol=@srv $rootpart /mnt/srv
sudo mount -o $mount_opts,subvol=@cache $rootpart /mnt/var/cache
sudo mount -o $mount_opts,subvol=@log $rootpart /mnt/var/log
sudo mount -o $mount_opts,subvol=@tmp $rootpart /mnt/var/tmp
sudo mount $efipart /mnt/boot/efi

# Detecting CPU vendor, necessary for microcode
[[ $(grep 'vendor' /proc/cpuinfo) == *"Intel"* ]] && ucode="intel-ucode"
[[ $(grep 'vendor' /proc/cpuinfo) == *"Amd"* ]] && ucode="amd-ucode"
echo "info: detected microcode - $ucode"

# Tweaking Pacman for better download speeds and fun cosmetic stuff
echo "info: tweaking pacman for better download speeds and cosmetic stuff"
sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf

# Installing base packages and defining the filesystem options
echo "info: installing base packages"
basestrap /mnt base base-devel dinit elogind-dinit btrfs-progs $ucode fish dhcpcd dhcpcd-dinit cups cups-dinit hplip system-config-printer
basestrap /mnt linux-firmware linux-zen linux-zen-headers grub os-prober efibootmgr mkinitcpio
echo "info: generating fstab"
sudo fstabgen -U /mnt > /mnt/etc/fstab

# Running the chroot script
# First, the arguments get passed to the chroot script
# Then, the chroot script gets run
installopts () {
    echo init=$init mydisk=$mydisk efipart=$efipart rootpart=$rootpart \
         ucode=$ucode region_city=$region_city myhost=$myhost rootpass=$rootpass
}

sudo cp chroot.sh /mnt/root && \
sudo cp postinstall.sh /mnt/home && \
sudo $(installopts) artix-chroot /mnt /bin/bash -c 'sh /root/chroot.sh; rm /root/chroot.sh; exit' && \
printf "info: installation complete\ninfo: you may chroot back to the system for further changes\ninfo: alternatively, you may automate the process as follows:\ninfo: reboot, login as root, run 'sh postinstall.sh'\n"
