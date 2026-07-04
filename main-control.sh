#!/bin/bash

#suite=plucky
suite=forky
#Uri="http://ftp.udx.icscoe.jp/Linux/debian/"
Uri="http://ftp.us.debian.org/debian/"

sudo apt-get install debian-archive-keyring


	start_time=`date`

	sudo rm -f log?
	sudo ./build_kernel_env.sh orangepi-5-rk3588s_defconfig $Uri $suite kernel
	#sudo ./meas-build-env.sh arm64 $1 $Uri $suite
	#sudo ./meas-build-env.sh arm64 ubuntu $Uri $suite
	echo "########################## ROOTFS START ############################"
	sudo ./rootfs-bootstrap.sh arm64 $Uri $suite
	echo "########################## ROOTFS END ############################"
	sudo ./disk_image.sh arm64 orangepi-5 rk3588s-orangepi-5
	sudo mv overlay/u-boot-rockchip.bin overlay/orangepi-5-u-boot-rockchip.bin
	sudo ./build_kernel_env.sh orangepi-5-plus-rk3588_defconfig $Uri $suite u-boot
	sudo ./disk_image.sh arm64 orangepi-5-plus rk3588-orangepi-5-plus
	sudo mv overlay/u-boot-rockchip.bin overlay/orangepi-5-PLUS-u-boot-rockchip.bin

	echo "$start_time"
	date
