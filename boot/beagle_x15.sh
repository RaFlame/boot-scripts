#!/bin/sh -e
#
# Copyright (c) 2013-2017 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

log="beagle_x15:"

#Make sure the cpu_thermal zone is enabled...
if [ -f /sys/class/thermal/thermal_zone0/mode ] ; then
	echo enabled > /sys/class/thermal/thermal_zone0/mode
fi

#Bus 005 Device 014: ID 1d6b:0104 Linux Foundation Multifunction Composite Gadget
usb_gadget="/sys/kernel/config/usb_gadget"

#  idVendor           0x1d6b Linux Foundation
#  idProduct          0x0104 Multifunction Composite Gadget
#  bcdDevice            4.04
#  bcdUSB               2.00

usb_idVendor="0x1d6b"
usb_idProduct="0x0104"
usb_bcdDevice="0x0404"
usb_bcdUSB="0x0200"
usb_serialnr="000000"
usb_product="USB Device"

#usb0 mass_storage
usb_ms_cdrom=0
usb_ms_ro=1
usb_ms_stall=0
usb_ms_removable=1
usb_ms_nofua=1

#*.iso priority over *.img
if [ -f /var/local/bb_usb_mass_storage.iso ] ; then
	usb_image_file="/var/local/bb_usb_mass_storage.iso"
elif [ -f /var/local/bb_usb_mass_storage.img ] ; then
	usb_image_file="/var/local/bb_usb_mass_storage.img"
fi

unset dnsmasq_usb0_usb1

if [ ! "x${usb_image_file}" = "x" ] ; then
	echo "${log} usb_image_file=[`readlink -f ${usb_image_file}`]"
fi

usb_iserialnumber="1234BBBK5678"
usb_iproduct="BeagleBoardX15"
usb_manufacturer="BeagleBoard.org"

#udhcpd gets started at bootup, but we need to wait till g_multi is loaded, and we run it manually...
if [ -f /var/run/udhcpd.pid ] ; then
	echo "${log} [/etc/init.d/udhcpd stop]"
	/etc/init.d/udhcpd stop || true
fi

use_libcomposite () {
	echo "${log} use_libcomposite"
	unset has_img_file
	if [ -f ${usb_image_file} ] ; then
		actual_image_file=$(readlink -f ${usb_image_file} || true)
		if [ ! "x${actual_image_file}" = "x" ] ; then
			if [ -f ${actual_image_file} ] ; then
				has_img_file="true"
				test_usb_image_file=$(echo ${actual_image_file} | grep .iso || true)
				if [ ! "x${test_usb_image_file}" = "x" ] ; then
					usb_ms_cdrom=1
				fi
			else
				echo "${log} FIXME: no usb_image_file"
			fi
		else
			echo "${log} FIXME: no usb_image_file"
		fi
	fi
	echo "${log} modprobe libcomposite"
	modprobe libcomposite || true
	if [ -d /sys/module/libcomposite ] ; then
		if [ -d ${usb_gadget} ] ; then
			if [ ! -d ${usb_gadget}/g_multi/ ] ; then
				echo "${log} Creating g_multi"
				mkdir -p ${usb_gadget}/g_multi || true
				cd ${usb_gadget}/g_multi

				echo ${usb_bcdUSB} > bcdUSB
				echo ${usb_idVendor} > idVendor # Linux Foundation
				echo ${usb_idProduct} > idProduct # Multifunction Composite Gadget
				echo ${usb_bcdDevice} > bcdDevice

				#0x409 = english strings...
				mkdir -p strings/0x409

				echo ${usb_iserialnumber} > strings/0x409/serialnumber
				echo ${usb_imanufacturer} > strings/0x409/manufacturer
				cat /proc/device-tree/model > strings/0x409/product

				mkdir -p functions/rndis.usb0
				# first byte of address must be even
				HOST=$(cat /proc/device-tree/model /etc/dogtag |md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
				SELF=$(cat /proc/device-tree/model /etc/rcn-ee.conf |md5sum|sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
				echo "${log} rndis.usb0/host_addr=[${HOST}]"
				echo ${HOST} > functions/rndis.usb0/host_addr
				echo "${log} rndis.usb0/dev_addr=[${SELF}]"
				echo ${SELF} > functions/rndis.usb0/dev_addr

#				mkdir -p functions/ecm.usb0
#				echo ${cpsw_4_mac} > functions/ecm.usb0/host_addr
#				echo ${cpsw_5_mac} > functions/ecm.usb0/dev_addr

				mkdir -p functions/acm.usb0

				if [ "x${has_img_file}" = "xtrue" ] ; then
					mkdir -p functions/mass_storage.usb0
					echo ${usb_ms_stall} > functions/mass_storage.usb0/stall
					echo ${usb_ms_cdrom} > functions/mass_storage.usb0/lun.0/cdrom
					echo ${usb_ms_nofua} > functions/mass_storage.usb0/lun.0/nofua
					echo ${usb_ms_removable} > functions/mass_storage.usb0/lun.0/removable
					echo ${usb_ms_ro} > functions/mass_storage.usb0/lun.0/ro
					echo ${actual_image_file} > functions/mass_storage.usb0/lun.0/file
				fi

				mkdir -p configs/c.1/strings/0x409
				echo "Multifunction with RNDIS" > configs/c.1/strings/0x409/configuration

				echo 500 > configs/c.1/MaxPower

				ln -s functions/rndis.usb0 configs/c.1/
				#ln -s functions/ecm.usb0 configs/c.1/
				ln -s functions/acm.usb0 configs/c.1/
				if [ "x${has_img_file}" = "xtrue" ] ; then
					ln -s functions/mass_storage.usb0 configs/c.1/
				fi

				#ls /sys/class/udc
				echo 488d0000.usb > UDC
				usb0="enable"
				#usb1="enable"
				echo "${log} g_multi Created"
			else
				echo "${log} FIXME: need to bring down g_multi first, before running a second time."
			fi
		else
			echo "${log} ERROR: no [${usb_gadget}]"
		fi
	else
		echo "${log} ERROR: [libcomposite didn't load]"
	fi
}

use_libcomposite

if [ -f /var/lib/misc/dnsmasq.leases ] ; then
	systemctl stop dnsmasq || true
	rm -rf /var/lib/misc/dnsmasq.leases || true
fi

if [ "x${usb0}" = "xenable" ] ; then
	echo "${log} Starting usb0 network"
	# Auto-configuring the usb0 network interface:
	$(dirname $0)/autoconfigure_usb0.sh || true
fi

if [ "x${usb1}" = "xenable" ] ; then
	echo "${log} Starting usb1 network"
	# Auto-configuring the usb1 network interface:
	$(dirname $0)/autoconfigure_usb1.sh || true
fi

if [ "x${dnsmasq_usb0_usb1}" = "xenabled" ] ; then
	if [ -d /sys/kernel/config/usb_gadget ] ; then
		/etc/init.d/udhcpd stop || true

		if [ -d /etc/dnsmasq.d/ ] ; then
			echo "${log} dnsmasq: setting up for usb0/usb1"
			disable_connman_dnsproxy

			wfile="/etc/dnsmasq.d/SoftAp0"
			echo "interface=usb0" > ${wfile}
			echo "interface=usb1" >> ${wfile}
			echo "port=53" >> ${wfile}
			echo "dhcp-authoritative" >> ${wfile}
			echo "domain-needed" >> ${wfile}
			echo "bogus-priv" >> ${wfile}
			echo "expand-hosts" >> ${wfile}
			echo "cache-size=2048" >> ${wfile}
			echo "dhcp-range=usb0,192.168.7.1,192.168.7.1,2m" >> ${wfile}
			echo "dhcp-range=usb1,192.168.6.1,192.168.6.1,2m" >> ${wfile}
			echo "listen-address=127.0.0.1" >> ${wfile}
			echo "listen-address=192.168.7.2" >> ${wfile}
			echo "listen-address=192.168.6.2" >> ${wfile}
			echo "dhcp-option=usb0,3" >> ${wfile}
			echo "dhcp-option=usb0,6" >> ${wfile}
			echo "dhcp-option=usb1,3" >> ${wfile}
			echo "dhcp-option=usb1,6" >> ${wfile}
			echo "dhcp-leasefile=/var/run/dnsmasq.leases" >> ${wfile}

			systemctl restart dnsmasq || true
		else
			echo "${log} ERROR: dnsmasq is not installed"
		fi
	fi
fi

if [ -d /sys/class/tty/ttyGS0/ ] ; then
	echo "${log} Starting serial-getty@ttyGS0.service"
	systemctl start serial-getty@ttyGS0.service || true
fi

if [ -f /usr/bin/amixer ] ; then
	#setup rca jacks for audio in/out:
	amixer -c0 sset 'PCM' 119
	amixer -c0 sset 'Line DAC' 108
	amixer -c0 sset 'Left PGA Mixer Mic2L' unmute
	amixer -c0 sset 'Right PGA Mixer Mic2R' unmute
	#amixer -c0 sset 'PGA' 10
	amixer -c0 sset 'PGA' 30
fi

#Just Cleanup /etc/issue, systemd starts up tty before these are updated...
sed -i -e '/Address/d' /etc/issue || true

#
