
.PHONY: vfio network

export PATH:=$(PATH):/usr/share/openvswitch/scripts
export DB_SOCK=/var/run/openvswitch/db.sock

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
	sudo ovs-vsctl add-port ovsdpdkbr0 vport1 -- add-port ovsdpdkbr0 vport2
	sudo ovs-vsctl show

id_rsa:
	ssh-keygen -t rsa -b 4096 -N '' -f id_rsa

cidata-x86.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	# src/userdata.py -o cidata/user-data -r -n virtamd64 -p grub-efi
	mkisofs -J -V cidata -o cidata-x86.iso cidata/

cidata-riscv64.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -n virtriscv64 -p 'linux-starfive flash-kernel qemu-system-misc'
	mkisofs -J -V cidata -o cidata-riscv64.iso cidata/

amd64.img: cidata-x86.iso kinetic-server-cloudimg-amd64.raw
	cp kinetic-server-cloudimg-amd64.raw amd64.img

x86_VARS.fd:
	dd if=/dev/zero of=x86_VARS.fd bs=540672 count=1

x86: amd64.img x86_VARS.fd cidata-x86.iso
	qemu-system-x86_64 \
        -M q35 -cpu host -accel kvm -m 4G -smp 4 \
        -nographic \
        -drive file=amd64.img,format=raw,if=virtio \
        -drive file=cidata-x86.iso,format=raw,if=virtio \
        -global driver=cfi.pflash01,property=secure,value=off \
        -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
        -drive if=pflash,format=raw,unit=1,file=x86_VARS.fd \
        -device virtio-net-pci,netdev=eth0 \
        -netdev user,id=eth0,hostfwd=tcp::8023-:22 \
        -device virtio-net-pci,netdev=eth1 \
        -netdev user,id=eth1
