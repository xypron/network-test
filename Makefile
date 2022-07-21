
.PHONY: vfio network
.PRECIOUS: nvme_%.img riscv64_%.img cidata-riscv64_%.iso amd64_%.img amd64_VARS_%.fd cidata-amd64_%.iso

export PATH:=$(PATH):/usr/share/openvswitch/scripts
export DB_SOCK=/var/run/openvswitch/db.sock

kinetic-server-cloudimg-amd64.raw:
	sudo umount /mnt || true
	sudo mount /dev/vdb /mnt -o ro
	qemu-img convert -f qcow2 -O raw /mnt/kinetic-server-cloudimg-amd64.img kinetic-server-cloudimg-amd64.raw
	sudo umount /mnt

kinetic-server-cloudimg-riscv64.raw:
	sudo umount /mnt || true
	sudo mount /dev/vdb /mnt -o ro
	qemu-img convert -f qcow2 -O raw /mnt/kinetic-server-cloudimg-riscv64.img kinetic-server-cloudimg-riscv64.raw
	sudo umount /mnt

vfio:
	# Prepare for using DPDK
	sudo modprobe vfio enable_unsafe_noiommu_mode=1
	sudo modprobe vfio-pci
	echo 1 | sudo tee -a /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
	sudo dpdk-devbind.py --bind=vfio-pci 0000:00:03.0
	sudo dpdk-devbind.py --status

network: vfio
	sudo update-alternatives --set ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk
	sudo /usr/share/openvswitch/scripts/ovs-ctl stop
	sudo /usr/share/openvswitch/scripts/ovs-ctl --system-id=random start
	sudo ovs-vsctl del-br ovsdpdkbr0 || /bin/true
	sudo ip tuntap del mode tap vport1 || /bin/true
	sudo ip tuntap del mode tap vport2 || /bin/true
	sudo ovs-vsctl add-br ovsdpdkbr0 -- set bridge ovsdpdkbr0 datapath_type=netdev
	sudo ovs-vsctl set Bridge ovsdpdkbr0 datapath_type=netdev
	sudo ovs-vsctl add-port ovsdpdkbr0 dpdk0 -- set Interface dpdk0 type=dpdk "options:dpdk-devargs=0000:00:03.0"
	sudo ifconfig ovsdpdkbr0
	sudo dhclient ovsdpdkbr0
	sudo ip tuntap add mode tap vport1
	sudo ip tuntap add mode tap vport2
	sudo ifconfig vport1 up
	sudo ifconfig vport2 up
	sudo ovs-vsctl add-port ovsdpdkbr0 vport1 -- \
	set Interface vport1 type=dpdkvhostuserclient \
	options:vhost-server-path=/tmp/vsock1
	sudo ovs-vsctl add-port ovsdpdkbr0 vport2 -- \
	set Interface vport2 type=dpdkvhostuserclient \
	options:vhost-server-path=/tmp/vsock2
	#sudo ifconfig vport1 10.0.2.201 netmask 255.255.255.0 up
	#sudo ifconfig vport2 10.0.2.202 netmask 255.255.255.0 up
	#sudo ovs-ofctl add-flow ovsdpdkbr0 in_port=2,action=output:3
	#sudo ovs-ofctl add-flow ovsdpdkbr0 in_port=3,action=output:2
	sudo ovs-vsctl show
	sudo ovs-ofctl dump-ports ovsdpdkbr0
	sudo ovs-ofctl show ovsdpdkbr0
	sudo ovs-ofctl dump-flows ovsdpdkbr0

id_rsa:
	ssh-keygen -t rsa -b 4096 -N '' -f id_rsa

cidata-riscv64_%.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -n c$*-riscv64 -p 'daemonize grub-efi make net-tools dpdk spdk'
	mkisofs -J -V cidata -o cidata-riscv64_$*.iso cidata/

cidata-amd64_%.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -n c$*-amd64 -p 'daemonzize grub-efi net-tools dpdk make spdk'
	mkisofs -J -V cidata -o cidata-amd64_$*.iso cidata/

riscv64_%.img: kinetic-server-cloudimg-riscv64.raw
	cp kinetic-server-cloudimg-riscv64.raw riscv64_$*.img
	qemu-img resize -f raw riscv64_$*.img 5G

amd64_%.img: kinetic-server-cloudimg-amd64.raw
	cp kinetic-server-cloudimg-amd64.raw amd64_$*.img

amd64_VARS_%.fd:
	dd if=/dev/zero of=amd64_VARS_$*.fd bs=540672 count=1

nvme_%.img:
	dd if=/dev/zero of=nvme_$*.img bs=128M count=1

rv_%: riscv64_%.img cidata-riscv64_%.iso nvme_%.img
	# Memory must be in shared hugpages
	# mrg_rxbuf is not useful for DPDK (cf. https://mails.dpdk.org/archives/dev/2019-June/135298.html)
	qemu-system-riscv64 \
	-M virt -cpu host -accel kvm -m 4G -smp 4 \
	-bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.elf \
	-kernel /usr/lib/u-boot/qemu-riscv64_smode/uboot.elf \
	-nographic \
	-object memory-backend-file,id=mem,size=4096M,mem-path=/dev/hugepages,share=on \
	-numa node,memdev=mem \
	-mem-prealloc \
	-drive file=riscv64_$*.img,format=raw,if=virtio \
	-drive file=cidata-riscv64_$*.iso,format=raw,if=virtio \
	-device virtio-rng-pci \
	-device virtio-net-pci,mac=00:00:00:00:0$*:01,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::802$*-:22 \
	-chardev socket,id=char1,server=on,path=/tmp/vsock$* \
	-device virtio-net-pci,mac=00:00:00:00:0$*:02,netdev=eth1,mrg_rxbuf=off \
	-netdev type=vhost-user,id=eth1,chardev=char1,vhostforce=on,queues=2 \
	-drive file=nvme_$*.img,format=raw,if=none,id=NVME1 \
	-device nvme,drive=NVME1,serial=nvme-1 \
	-device virtio-rng-pci

x86_%: amd64_%.img amd64_VARS_%.fd cidata-amd64_%.iso nvme_%.img
	# Memory must be in shared hugpages
	# mrg_rxbuf is not useful for DPDK (cf. https://mails.dpdk.org/archives/dev/2019-June/135298.html)
	qemu-system-x86_64 \
	-M q35 -cpu host -accel kvm -m 4G -smp 4 \
	-nographic \
	-object memory-backend-file,id=mem,size=4096M,mem-path=/dev/hugepages,share=on \
	-numa node,memdev=mem \
	-mem-prealloc \
	-drive file=amd64_$*.img,format=raw,if=virtio \
	-drive file=cidata-amd64_$*.iso,format=raw,if=virtio \
	-global driver=cfi.pflash01,property=secure,value=off \
	-drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
	-drive if=pflash,format=raw,unit=1,file=amd64_VARS_$*.fd \
	-device virtio-net-pci,mac=00:00:00:00:0$*:01,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::802$*-:22 \
	-chardev socket,id=char1,server=on,path=/tmp/vsock$* \
	-device virtio-net-pci,mac=00:00:00:00:0$*:02,netdev=eth1,mrg_rxbuf=off \
	-netdev type=vhost-user,id=eth1,chardev=char1,vhostforce=on,queues=2 \
	-drive file=nvme_$*.img,format=raw,if=none,id=NVME1 \
	-device nvme,drive=NVME1,serial=nvme-1

loginx86_%:
	ssh -i id_rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 802$*

altloginx86_%:
	ssh -i id_rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 803$*
