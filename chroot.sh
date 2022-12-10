#!/bin/bash -e

#     ___         __  _      ____           __        ____
#    /   |  _____/ /_(_)  __/  _/___  _____/ /_____ _/ / /__  _____
#   / /| | / ___/ __/ / |/_// // __ \/ ___/ __/ __ `/ / / _ \/ ___/
#  / ___ |/ /  / /_/ />  <_/ // / / (__  ) /_/ /_/ / / /  __/ /
# /_/  |_/_/   \__/_/_/|_/___/_/ /_/____/\__/\__,_/_/_/\___/_/
#
# STAGE 2: CHROOT

# loading cpu,gpu,ram,boot,disk,diskdir,efipart,rootpart,username,userpass,rootpass
tmpvardir="/tmpvars"
cpu=$(cat ${tmpvardir}/cpu)
gpu=$(cat ${tmpvardir}/gpu)
ram=$(cat ${tmpvardir}/ram)
boot=$(cat ${tmpvardir}/boot)
disk=$(cat ${tmpvardir}/disk)
disk=$(cat ${tmpvardir}/diskdir)
efipart=$(cat ${tmpvardir}/efipart)
rootpart=$(cat ${tmpvardir}/rootpart)
username=$(cat ${tmpvardir}/username)
userpass=$(cat ${tmpvardir}/userpass)
rootpass=$(cat ${tmpvardir}/rootpass)
hostname=$(cat ${tmpvardir}/hostname)
timezone=$(cat ${tmpvardir}/timezone)

# configuring localization and stuff
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
printf "LANG=en_US.UTF-8\nLC_COLLATE=C\n" > /etc/locale.conf
ln -s /usr/share/zoneinfo/${timezone} /etc/localtime

locale-gen
hwclock --systohc --utc

# user configuration
useradd -mG wheel,video,audio,input -s /bin/bash ${username}
echo -e "${rootpass}\n${rootpass}\n" | passwd
echo -e "${userpass}\n${userpass}\n" | passwd ${username}

# hostname configuration
printf "\n127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t${hostname}.localdomain\t${hostname}\n" >> /etc/hosts

# installing GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Artix --recheck
grub-mkconfig -o /boot/grub/grub.cfg
