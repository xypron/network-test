linux:
	rm linux/ -rf
	git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git --depth 1 linux/ -b v5.19-rc7

linux-image-5.19.0-rc7_5.19.0-rc7-1_riscv64.deb:
	rm -f linux*.deb
	rm -f linux/.version
	cd linux && git fetch --depth 1 origin v5.19-rc7
	cd linux && ARCH=riscv make defconfig
	cp config-5.19-rc7 linux/.config
	cd linux && ARCH=riscv make olddefconfig
	cd linux && ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- make bindeb-pkg -j$$(nproc)

id_rsa:
	ssh-keygen -t rsa -b 4096 -N '' -f id_rsa

kinetic-server-cloudimg-amd64.img:
	wget https://cloud-images.ubuntu.com/kinetic/current/kinetic-server-cloudimg-amd64.img

cidata-amd64.iso: id_rsa
	rm -rf cidata/
	mkdir cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -n virtamd64 -p 'genisoimage grub-efi make net-tools qemu-system-x86'
	mkisofs -J -V cidata -o cidata-amd64.iso cidata/

kinetic-server-cloudimg-riscv64.img:
	wget http://cloud-images.ubuntu.com/kinetic/current/kinetic-server-cloudimg-riscv64.img

cidata-riscv64.iso: id_rsa linux-image-5.19.0-rc7_5.19.0-rc7-1_riscv64.deb kinetic-server-cloudimg-riscv64.img
	rm -rf cidata/
	mkdir cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	echo Package: "openvswitch*\nPin: release o=LP-PPA-ubuntu-risc-v-team-develop\nPin-Priority: 900" \
	> cidata/ppa_pin
	cp linux-image-5.19.0-rc7_5.19.0-rc7-1_riscv64.deb cidata/
	cp kinetic-server-cloudimg-riscv64.img cidata/
	src/userdata.py -o cidata/user-data -n virtriscv64 -p 'genisoimage grub-efi make net-tools qemu-system-misc u-boot-qemu'
	mkisofs -J -V cidata -o cidata-riscv64.iso cidata/

kinetic-server-cloudimg-amd64.raw: kinetic-server-cloudimg-amd64.img
	qemu-img convert -f qcow2 -O raw kinetic-server-cloudimg-amd64.img kinetic-server-cloudimg-amd64.raw

amd64.img: kinetic-server-cloudimg-amd64.raw
	cp kinetic-server-cloudimg-amd64.raw amd64.img
	qemu-img resize -f raw amd64.img 16G

kinetic-server-cloudimg-riscv64.raw: kinetic-server-cloudimg-riscv64.img
	qemu-img convert -f qcow2 -O raw kinetic-server-cloudimg-riscv64.img kinetic-server-cloudimg-riscv64.raw

riscv64.img: kinetic-server-cloudimg-riscv64.raw
	cp kinetic-server-cloudimg-riscv64.raw riscv64.img
	qemu-img resize -f raw riscv64.img 16G

VARS-amd64.fd:
	dd if=/dev/zero of=VARS-amd64.fd bs=540672 count=1

x86: cidata-amd64.iso amd64.img VARS-amd64.fd
	qemu-system-x86_64 \
	-M q35 -cpu host -accel kvm -m 12G -smp 8 \
	-nographic \
	-drive file=amd64.img,format=raw,if=virtio \
	-drive file=cidata-amd64.iso,format=raw,if=virtio \
	-global driver=cfi.pflash01,property=secure,value=off \
	-drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
	-drive if=pflash,format=raw,unit=1,file=VARS-amd64.fd \
	-device virtio-net-pci,netdev=eth0,mq=on \
	-netdev user,id=eth0,hostfwd=tcp::8031-:22 \
	-device virtio-net-pci,netdev=eth1,mq=on \
	-netdev user,id=eth1,hostfwd=tcp::8032-:22

rv: cidata-riscv64.iso riscv64.img
	qemu-system-riscv64 \
	-M virt -accel tcg -m 16G -smp 8 \
	-nographic \
	-serial mon:stdio \
	-device qemu-xhci \
	-device usb-kbd \
	-bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin \
	-kernel /usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin \
	-drive file=riscv64.img,format=raw,if=virtio \
	-drive file=cidata-riscv64.iso,format=raw,if=virtio \
	-device virtio-net-pci,netdev=eth0,rombar=0,romfile= \
	-netdev user,id=eth0,hostfwd=tcp::8041-:22 \
	-device virtio-net-pci,netdev=eth1,mq=on,rombar=0,romfile= \
	-netdev user,id=eth1,hostfwd=tcp::8042-:22

rvchild:
	qemu-system-riscv64 \
	-M virt -accel kvm -m 2G -smp 2 \
	-nographic \
	-kernel /mnt/boot/vmlinuz \
	-initrd /mnt/boot/initrd.img \
	-append 'root=LABEL=cloudimg-rootfs earlycon' \
	-drive file=kinetic-server-cloudimg-riscv64.raw,format=raw,if=virtio \
	-device virtio-net-device,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::8022-:22

prepare:
	ssh-keygen -t rsa -b 4096 -f id_rsa -P ''
	src/userdata.py -o cidata/user-data

loginx86:
	ssh -i id_rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 8031 || true

loginrv:
	ssh -i id_rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 8041 || true
