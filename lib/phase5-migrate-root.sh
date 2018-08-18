#!/bin/bash

################################################################################

# %ELIB% - this line indicates that ELIB should be injected below

################################################################################

# we need to detect disk device names and partition names
# as disk name could vary depending on instance type
DISK1=$(find_disk1)
DISK2=$(find_disk2)
DISK1P1=$(append_disk_part $DISK1 1)
DISK2P1=$(append_disk_part $DISK2 1)

################################################################################

# in debug mode partitions could be still mounted by previous failed attempt
if mount | grep -q /mnt/gentoo; then
    einfo "Unmounting partitions..."

    qexec umount /mnt/gentoo/dev/pts
    qexec umount /mnt/gentoo/dev
    qexec umount /mnt/gentoo/sys
    qexec umount /mnt/gentoo/proc

    eexec umount /mnt/gentoo
fi

################################################################################

einfo "Preparing disk 1..."

eindent

einfo "Creating partitions..."

echo ";" | qexec sfdisk --label dos "$DISK1"
while [ ! -e $DISK1P1 ]; do sleep 1; done

einfo "Formatting partitions..."

eexec mkfs.ext4 -q $DISK1P1

einfo "Labeling partitions..."

eexec e2label $DISK1P1 /

eoutdent

################################################################################

einfo "Mounting disk 1..."

eexec mkdir -p /mnt/gentoo
eexec mount $DISK1P1 /mnt/gentoo

################################################################################

einfo "Migrating files from disk 2 to disk 1..."

# switch working directory
eexec cd /mnt/gentoo

# create auto generated directories
for i in home root media mnt opt proc sys dev tmp run; do
    eexec mkdir $i
    eexec touch $i/.keep
done

# fix permissions
eexec chmod 700 root
eexec chmod 1777 tmp

# copy everything with exception to autogenerated directories
eexec rsync --archive --xattrs --quiet \
    --exclude='/home' --exclude='/root' --exclude='/media' --exclude='/mnt' \
    --exclude='/opt' --exclude='/proc' --exclude='/sys' --exclude='/dev' \
    --exclude='/tmp' --exclude='/run' --exclude='/lost+found' \
    / /mnt/gentoo/

# clear ec2 init state if available
if [ -e "./var/lib/amazon-ec2-init.lock" ]; then
    eexec rm "./var/lib/amazon-ec2-init.lock"
fi

# reset hostname
echo "hostname=localhost" > "./etc/conf.d/hostname"

################################################################################

einfo "Mounting proc/sys/dev/pts..."

eexec mount -t proc none /mnt/gentoo/proc
eexec mount -o bind /sys /mnt/gentoo/sys
eexec mount -o bind /dev /mnt/gentoo/dev
eexec mount -o bind /dev/pts /mnt/gentoo/dev/pts

################################################################################

einfo "Fixing boot..."

eexec chroot /mnt/gentoo bash -s << END
set -e
# set -x

# updating configuration
env-update
source /etc/profile

# reinstalling grub to first disk
grub-install $DISK1
grub-mkconfig -o /boot/grub/grub.cfg

# changing root disk in fstab
sed -i -e '/^LABEL=/d' /etc/fstab
echo "LABEL=/ / ext4 noatime 0 1" >> /etc/fstab
END
