#!/bin/bash -e

#     ___         __  _      ____           __        ____
#    /   |  _____/ /_(_)  __/  _/___  _____/ /_____ _/ / /__  _____
#   / /| | / ___/ __/ / |/_// // __ \/ ___/ __/ __ `/ / / _ \/ ___/
#  / ___ |/ /  / /_/ />  <_/ // / / (__  ) /_/ /_/ / / /  __/ /
# /_/  |_/_/   \__/_/_/|_/___/_/ /_/____/\__/\__,_/_/_/\___/_/
#
# STAGE 1: INSTALL

# variables and functions for printing
delline="\e[2K"
upone="\e[1A"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
cyan="\e[36m"
reset="\e[39m"
oneup="\r${upone}${delline}${upone}"
twoup="${oneup}${oneup}"

printyellow()
{
    str="$1"
    printf "${yellow}${str}${reset}\n"
}

printred()
{
    str="$1"
    printf "${red}${str}${reset}\n"
}

printgreen()
{
    str="$1"
    printf "${green}${str}${reset}\n"
}

newline()
{
    printf "\n"
}


# detecting stuff
cpu=$(lscpu | grep "Vendor ID:" | awk '{print $NF}')
if [[ ${cpu} == "AuthenticAMD" ]]; then ucode="amd-ucode"; else ucode="intel-ucode"; fi
gpu=$(lspci | grep "VGA compatible controller:" | awk '{print $5}')
if [[ -d /sys/firmware/efi/efivars ]]; then boot="UEFI"; else boot="BIOS"; fi
ram=$(echo "$(echo "$(cat /proc/meminfo)" | grep "MemTotal" | awk '{print $2}') / 1000000" | bc)

# ask questions
choosedisk()
{
    state=""
    printyellow "available disks:"
    lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "name: "$2"\nsize: "$3"\n"}'
    printyellow "choose the disk name (e.g: sda) ${state}"
    until [[ -b "/dev/$disk" ]]; do
        read -p "(*): " disk
        ! [[ -b "/dev/$disk" ]] && printf "${oneup}" && newline
    done
    diskdir="/dev/$disk"
    efipart=${diskdir}1
    rootpart=${diskdir}2
    if [[ $disk == *"nvme"* ]]; then efipart="${diskdir}p1"; rootpart="${diskdir}p2"; fi
}

userdetails()
{
    read -p "root pass: " rootpass
    read -p "user name: " username
    read -p "user pass: " userpass
    read -p "hostname: " hostname
}

asktimezone()
{
    region="incorrect"
    city="incorrect"
    printyellow "available regions:"
    echo -e "$(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -printf '%f ')\n" | fold -s -w 45
    printyellow "choose the correct region"
    until [[ -d /usr/share/zoneinfo/${region} ]]; do
        read -p "(*): " region
        ! [[ -d /usr/share/zoneinfo/${region} ]] && printf "${oneup}" && newline
    done
    printyellow "available cities:"
    echo -e "$(find /usr/share/zoneinfo/${region} -printf '%f ')\n" | fold -s -w 80
    printyellow "choose the correct city"
    until [[ -f /usr/share/zoneinfo/${region}/${city} ]]; do
        read -p "(*): " city
        ! [[ -f /usr/share/zoneinfo/$region/${city} ]] && printf "${oneup}" && newline
    done
    timezone="${region}/${city}"
    printgreen ${timezone}
}


executeinstall()
{
    # unmounting everything to make sure that the installation will go smoothly
    umount -A --recursive /mnt
    umount -A --recursive $diskdir
    swapoff -a $diskdir

    # partition management
    printf "label: gpt\n,512M,U\n,,L\n" | sfdisk ${diskdir}
    mkfs.vfat -F32 -n "EFI" ${efipart}
    mkfs.btrfs -L "ROOT" -f ${rootpart}

    mount ${rootpart} /mnt
    mountopts="defaults,noatime,compress=zstd,discard=async,ssd"

    btrfs sub create /mnt/@
    btrfs sub create /mnt/@home
    btrfs sub create /mnt/@root
    btrfs sub create /mnt/@srv
    btrfs sub create /mnt/@cache
    btrfs sub create /mnt/@log
    btrfs sub create /mnt/@tmp

    umount /mnt

    mount -o ${mountopts},subvol=@ ${rootpart} /mnt
    mkdir -p /mnt/{boot/efi,home,root,srv,var/{cache,log,tmp}}
    mount -o ${mountopts},subvol=@home ${rootpart} /mnt/home
    mount -o ${mountopts},subvol=@root ${rootpart} /mnt/root
    mount -o ${mountopts},subvol=@srv ${rootpart} /mnt/srv
    mount -o ${mountopts},subvol=@cache ${rootpart} /mnt/var/cache
    mount -o ${mountopts},subvol=@log ${rootpart} /mnt/var/log
    mount -o ${mountopts},subvol=@tmp ${rootpart} /mnt/var/tmp
    mount ${efipart} /mnt/boot/efi

    # exporting configuration
    tmpvardir="/mnt/tmpvars"
    if [[ -d ${tmpvardir} ]]; then rm -r ${tmpvardir} && mkdir ${tmpvardir}; fi
    mkdir ${tmpvardir}
    touch ${tmpvardir}/{cpu,gpu,ram,boot,disk,diskdir,efipart,rootpart,username,userpass,rootpass,hostname,timezone}
    for file in ${tmpvardir}/*
    do
        var=${file##*/}
        printf "${!var}" > ${file}
    done

    # tweaking Pacman (faster basestrap download + prettier output)
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf

    pacman -Sy --noconfirm wget refind gdisk

    # installing essential packages through basestrap
    basestrap /mnt base base-devel elogind elogind-dinit opendoas booster refind gdisk \
                   linux-zen linux-zen-headers linux-firmware \
                   ntfs-3g dhcpcd dhcpcd-dinit networkmanager networkmanager-dinit cups cups-dinit hplip \
                   system-config-printer mkinitcpio \
                   pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber


    # tweaking Pacman for soon-to-be chrooted system
    cp -f configs/pacman.conf /mnt/etc
    wget https://github.com/archlinux/svntogit-packages/raw/packages/pacman-mirrorlist/trunk/mirrorlist -O /mnt/etc/pacman.d/mirrorlist-arch

    # shortcut for configuring doas
    printf "permit persist keepenv $username as root\npermit nopass $username as root cmd /usr/bin/poweroff\npermit nopass $username as root cmd /usr/bin/reboot\n" > /mnt/etc/doas.conf

    # generating fstab
    fstabgen -U /mnt >> /mnt/etc/fstab

    # chroot time
    artix-chroot /mnt chroot.sh
}

verifydetails()
{
    printyellow "COMPUTER INFO"
    printyellow "CPU: ${green}${cpu}"
    printyellow "GPU: ${green}${gpu}"
    printyellow "RAM: ${green}${ram}GB"
    printyellow "BOOT MODE: ${green}${boot}"
    newline
    printyellow "INSTALL INFO:"
    printyellow "DISK: ${green}${disk}"
    printyellow "EFI PARTITION: ${green}${efipart}"
    printyellow "ROOT PARTITION: ${green}${rootpart}"
    printyellow "USER DETAILS (name:pass): ${cyan}${username}:${userpass}"
    printyellow "ROOT DETAILS (name:pass): ${cyan}root:${rootpass}"
    printyellow "HOSTNAME: ${green}${hostname}"
    printyellow "TIMEZONE : ${green}${timezone}"
    newline
    printyellow "do you want to install? (y/Y/n/N)"
    until [[ ${installchoice} == "y" || ${installchoice} == "Y" || ${installchoice} == "n" || ${installchoice} == "N" ]]; do
        read -p "(*): " -n 1 installchoice && newline
        ! [[ ${installchoice} == "y" || ${installchoice} == "Y" || ${installchoice} == "n" || ${installchoice} == "N" ]] && printf "${oneup}" && newline
    done
    [[ ${installchoice} == "n" || ${installchoice} == "N" ]] && printred "installation aborted..." && exit 1
    [[ ${installchoice} == "y" || ${installchoice} == "Y" ]] && clear && printyellow "INSTALLING ARTIX" && newline && newline && executeinstall
}

# aborting install if system is BIOS (will eventually support BIOS though, it shouldn't be hard to implement)
if [[ ${boot} == "BIOS" ]]; then printred "system runs in BIOS, aborting" && exit 1; fi

choosedisk
asktimezone
userdetails
verifydetails
