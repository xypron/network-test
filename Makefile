
.PHONY: vfio network

export PATH:=$(PATH):/usr/share/openvswitch/scripts
export DB_SOCK=/var/run/openvswitch/db.sock
export VHOST_USER_SOCKET_PATH=/tmp
export VHOST_USER_SOCKET_PATH_1:="$(VHOST_USER_SOCKET_PATH)/vhost-user-1"
export VHOST_USER_SOCKET_PATH_2:="$(VHOST_USER_SOCKET_PATH)/vhost-user-2"

kinetic-server-cloudimg-amd64.img:
	wget https://cloud-images.ubuntu.com/kinetic/current/kinetic-server-cloudimg-amd64.img

kinetic-server-cloudimg-amd64.raw: kinetic-server-cloudimg-amd64.img
	qemu-img convert -f qcow2 -O raw kinetic-server-cloudimg-amd64.img kinetic-server-cloudimg-amd64.raw

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
	sudo ip tuntap del mode tap vport1
	sudo ip tuntap del mode tap vport2
	sudo ovs-vsctl add-br ovsdpdkbr0 -- set bridge ovsdpdkbr0 datapath_type=netdev
	sudo ovs-vsctl add-port ovsdpdkbr0 dpdk0 -- set Interface dpdk0 type=dpdk "options:dpdk-devargs=0000:00:03.0"
	sudo ifconfig ovsdpdkbr0
	sudo dhclient ovsdpdkbr0
	sudo ip tuntap add mode tap vport1
	sudo ip tuntap add mode tap vport2
	sudo ifconfig vport1 up
	sudo ifconfig vport2 up
	sudo ovs-vsctl add-port ovsdpdkbr0 vport1 -- \
	set Interface vport1 type=dpdkvhostuserclient \
        options:vhost-server-path=$(VHOST_USER_SOCKET_PATH_1)
	sudo ovs-vsctl add-port ovsdpdkbr0 vport2 -- \
	set Interface vport2 type=dpdkvhostuserclient \
        options:vhost-server-path=$(VHOST_USER_SOCKET_PATH_2)
	#sudo ifconfig vport1 10.0.2.201 netmask 255.255.255.0 up
	#sudo ifconfig vport2 10.0.2.202 netmask 255.255.255.0 up
	sudo ovs-vsctl show
	sudo ovs-ofctl dump-ports ovsdpdkbr0
	sudo ovs-ofctl show ovsdpdkbr0

id_rsa:
	ssh-keygen -t rsa -b 4096 -N '' -f id_rsa

cidata-riscv64_%.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -n c$*-riscv64 -p 'linux-starfive flash-kernel qemu-system-misc'
	mkisofs -J -V cidata -o cidata-riscv64_$*.iso cidata/

cidata-amd64_%.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -n c$*-amd64 -p 'grub-efi spdk'
	mkisofs -J -V cidata -o cidata-amd64_$*.iso cidata/

amd64_%.img: kinetic-server-cloudimg-amd64.raw
	cp kinetic-server-cloudimg-amd64.raw amd64_$*.img

amd64_VARS_%.fd:
	dd if=/dev/zero of=amd64_VARS_$*.fd bs=540672 count=1

x86_%: amd64_%.img amd64_VARS_%.fd cidata-amd64_%.iso
	mkdir -p $(VHOST_USER_SOCKET_PATH)
	qemu-system-x86_64 \
        -M q35 -cpu host -accel kvm -m 4G -smp 4 \
        -nographic \
        -drive file=amd64_$*.img,format=raw,if=virtio \
        -drive file=cidata-amd64_$*.iso,format=raw,if=virtio \
        -global driver=cfi.pflash01,property=secure,value=off \
        -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
        -drive if=pflash,format=raw,unit=1,file=amd64_VARS_$*.fd \
        -device virtio-net-pci,netdev=eth0 \
        -netdev user,id=eth0,hostfwd=tcp::802$*-:22 \
	-chardev socket,id=char1,path=$(VHOST_USER_SOCKET_PATH_$*),server=on \
	-netdev type=vhost-user,id=eth1,chardev=char1,vhostforce=on \
	-device virtio-net-pci,mac=00:00:00:00:00:01,netdev=eth1

loginx86_%:
	ssh -i id_rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 802$*
