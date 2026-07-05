#!/bin/bash

set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

kernel=`ls kernel/linux*.deb|wc -l`
if [ $kernel -ne 5 ]; then
	echo "Build kernel first"
	exit 1
fi
set -x
#Bootstrap the system
rm -rf $1
mkdir $1
chroot_dir=$1
mem_size=`free --giga|grep Mem|awk '{print $2}'`
if [ $mem_size -gt 10 ]; then
	mount -t tmpfs -o size=10G tmpfs $chroot_dir
fi
rm -f wget-log* overlay/kernel_version

suite=$3
#suite=resolute
Uri=$2
#Uri="http://ports.ubuntu.com/ubuntu-ports"
	debootstrap --arch=arm64 $suite arm64 $Uri

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export  LC_ALL=C
export  LC_CTYPE=C
export  LANGUAGE=C
export  LANG=C 

#Setup DNS
echo "127.0.0.1 localhost" > $1/etc/hosts
echo "127.0.0.1 debian-desktop" > $1/etc/hosts
echo "nameserver 8.8.8.8" > $1/etc/resolv.conf
echo "nameserver 8.8.4.4" >> $1/etc/resolv.conf

#sources.list setup
rm $1/etc/hostname
echo "debian-desktop" > $1/etc/hostname
{
echo "Types: deb"
echo "URIs: $Uri"
echo "Suites: $suite $suite-updates $suite-backports"
echo "Components: main contrib non-free non-free-firmware"
echo "Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg"
echo ""
echo "## Ubuntu security updates. Aside from URIs and Suites,"
echo "## this should mirror your choices in the previous section."
echo "Types: deb"
echo "URIs: http://security.debian.org"
echo "Suites: $suite-security"
echo "Components: main contrib non-free non-free-firmware"
echo "Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg"
} > $1/etc/apt/sources.list.d/debian.sources
rm -f $1/etc/apt/sources.list

# kdump not install
#cat > "$1/etc/apt/preferences.d/no-kdump" << 'EOF'
#Package: kdump-tools
#Pin: release *
#Pin-Priority: -1
#EOF


#setup custom packages

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get update
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y upgrade
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get update
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y dist-upgrade
# もし他のパッケージでも同じように止まった場合は同じパターンで：
# echo 'パッケージ名 パッケージ名/質問キー boolean false' | debconf-set-selections
systemd-nspawn -D $1 \
  --resolv-conf=replace-host \
  --as-pid2 \
  apt-get -y install cinnamon lightdm initramfs-tools vim cloud-guest-utils e2fsprogs sudo zenity apt-utils task-japanese-gnome-desktop firmware-linux grub-efi-arm64 initramfs-tools fonts-noto-cjk systemd-timesyncd alsa-utils nautilus rsyslog vim
#firefox-esr-l10n-ja thunderbird-l10n-ja  task-gnome-desktop

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 /bin/bash -c "apt-get install -y gstreamer1.0-plugins-bad gstreamer1.0-plugins-good gstreamer1.0-tools clapper mpv vulkan-tools mesa-utils"

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y purge cloud-init flash-kernel fwupd nano grub-efi-arm64

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get update
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y upgrade

sed -i 's/#EXTRA_GROUPS=.*/EXTRA_GROUPS="video"/g' $1/etc/adduser.conf
sed -i 's/#ADD_EXTRA_GROUPS=.*/ADD_EXTRA_GROUPS=1/g' $1/etc/adduser.conf

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 useradd -m -s /bin/bash setupadmin
#echo "setupadmin password"
#systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 passwd setupadmin
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 usermod -aG sudo setupadmin

cp $1/etc/sudoers $1/etc/sudoers.org
echo 'setupadmin ALL=(ALL) NOPASSWD: ALL' >> $1/etc/sudoers

# ① GDM3の自動ログイン設定
mv $1/etc/lightdm/lightdm.conf $1/etc/lightdm/lightdm.conf.org
cat << 'EOF' > $1/etc/lightdm/lightdm.conf
[LightDM]

[Seat:*]
autologin-user=setupadmin
autologin-user-timeout=0

[XDMCPServer]

[VNCServer]

EOF

# ② 自動起動ファイルの配置（XDG Autostart）
mkdir -p $1/etc/xdg/autostart
cat << 'EOF' > $1/etc/xdg/autostart/first-boot-wizard.desktop
[Desktop Entry]
Type=Application
Name=First Boot Wizard
Exec=/usr/local/bin/gui-wizard.sh
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# ③ ウィザードスクリプトの配置
cat << 'EOF' > $1/usr/local/bin/gui-wizard.sh
#!/bin/bash

NEW_USER=$(zenity --entry --title="Initial Setup" --text="新しい一般ユーザー名>を入力してください:" --width=400)
[ -z "$NEW_USER" ] && reboot

while true; do
    PASS1=$(zenity --password --title="Initial Setup" --text="パスワードを設定>してください:")
    PASS2=$(zenity --password --title="Initial Setup" --text="もう一度パスワー>ドを入力してください:")
    if [ "$PASS1" = "$PASS2" ] && [ ! -z "$PASS1" ]; then
        break
    fi
    zenity --error --text="パスワードが一致しないか、空欄です。再入力してくださ
い。"
done

sudo useradd -m -s /bin/bash -G sudo,video,audio "$NEW_USER"
echo "$NEW_USER:$PASS1" | sudo chpasswd

sudo sed -i 's/AutomaticLoginEnable=true/#AutomaticLoginEnable=true/g' /etc/gdm3/daemon.conf
sudo sed -i 's/AutomaticLogin=setupadmin/#AutomaticLogin=setupadmin/g' /etc/gdm3/daemon.conf

sudo rm -f /etc/xdg/autostart/first-boot-wizard.desktop
sudo userdel -r setupadmin
sudo cp /etc/lightdm/lightdm.conf.org /etc/lightdm/lightdm.conf
sudo cp /etc/sudoers.org /etc/sudoers

zenity --info --text="設定が完了しました。システムを再起動します。" --width=300
sudo reboot
EOF

# 実行権限を付与
chmod +x $1/usr/local/bin/gui-wizard.sh



# kernel
mkdir $1/kkk && cp -r kernel $1/kkk && cp overlay/*.deb $1/kkk/
rm  $1/kkk/libdrm-dev_*.deb $1/kkk/libegl1-mesa-dev_*.deb $1/kkk/libgbm-dev_*.deb && \
rm  $1/kkk/libgl1-mesa-dev_*.deb $1/kkk/libgles2-mesa-dev_*.deb $1/kkk/mesa-common-dev_*.deb && \
rm  $1/kkk/mesa-opencl-icd_*.deb $1/kkk/mesa-teflon-delegate_*.deb $1/kkk/mesa-drm-shim_*.deb && \
rm  $1/kkk/libdrm-tests_*.deb 

systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 /bin/bash -c "apt-get -y purge \$(dpkg --list | grep -Ei 'linux-image|linux-headers|linux-modules|linux-rockchip' | awk '{ print \$2 }')"
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 /bin/bash -c "cd kkk && dpkg -i *.deb && dpkg -i kernel/*conservative*.deb && dpkg -i kernel/*ondemand*.deb"
#&& dpkg -i kernel/*conservative*.deb && dpkg -i kernel/*ondemand*.deb"

rm -rf $1/kkk
kernel_version="`ls -1 $1/boot/vmlinu?-*|sed 's#-# #g' | awk '{ print $2 }'|head -1`"
echo "kernel_version=$kernel_version" > overlay/kernel_version
# install U-Boot
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y install u-boot-tools u-boot-menu

# Default kernel command line arguments
echo -n "rootwait rw console=ttyS2,1500000 console=tty1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" > $1/etc/kernel/cmdline
echo -n " quiet splash plymouth.ignore-serial-consoles" >> $1/etc/kernel/cmdline

# Override u-boot-menu config
mkdir -p $1/usr/share/u-boot-menu/conf.d
cat << 'EOF' > $1/usr/share/u-boot-menu/conf.d/debian.conf
U_BOOT_UPDATE="true"
U_BOOT_PROMPT="1"
U_BOOT_PARAMETERS="$(cat /etc/kernel/cmdline)"
U_BOOT_TIMEOUT="20"
EOF

rm -f $1/var/lib/dbus/machine-id
true > $1/etc/machine-id
touch $1/var/log/syslog
chown root:adm $1/var/log/syslog
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 ssh-keygen -A
# debug
echo "linux-version"
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 linux-version list

# chromium
mkdir -p $1/etc/chromium.d/
echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-features=AcceleratedVideoDecoder,V4l2VideoDecode --disable-features=UseChromeOSDirectVideoDecoder"' > $1/etc/chromium.d/opi5-v4l2


systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get -y autoremove
systemd-nspawn -D $1 --resolv-conf=replace-host --as-pid2 apt-get  clean


rm -f wget-log*
rm -f $1/boot/*.old
#tar the rootfs
rootfs="overlay/debian.rootfs.tar.gz"
echo "rootfs=$rootfs" > overlay/rootfs
cd $1
rm -rf ../$rootfs
sync
echo " Now create $rootfs "
tar -zcf ../$rootfs --xattrs --xattrs-include='*' ./*
cd ..
echo "DISK usage"
df $1  
# Exit trap is no longer needed
trap '' EXIT
if [ $mem_size -gt 10 ]; then
	umount $1
	sleep 2
fi
exit 0
