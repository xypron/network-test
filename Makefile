
all:
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	cp kinetic-server-cloudimg-amd64.raw /tmp/amd64.img
	mkisofs -J -V cidata -o cidata.iso cidata/
	qemu-system-x86_64 \
	-M q35 -accel kvm -m 16G -smp 8 \
	-nographic \
	-drive file=/tmp/amd64.img,format=raw,if=virtio \
	-drive file=cidata.iso,format=raw,if=virtio \
	-device virtio-net-pci,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::8022-:22

rv:
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -r -p 'qemu-system-misc u-boot-qemu opensbi linux-image-starfive'
	cp kinetic-server-cloudimg-riscv64.raw /tmp/riscv64.img
	qemu-img resize /tmp/riscv64.img +8G
	mkisofs -J -V cidata -o cidata.iso cidata/
	qemu-system-riscv64 \
	-M virt -accel tcg -m 16G -smp 8 \
	-nographic \
	-serial mon:stdio \
	-device qemu-xhci \
	-device usb-kbd \
	-bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin \
	-kernel /usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin \
	-drive file=/tmp/riscv64.img,format=raw,if=virtio \
	-drive file=cidata.iso,format=raw,if=virtio \
	-device virtio-net-device,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::8022-:22

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

kinetic-server-cloudimg-riscv64.img:
	wget http://cloud-images.ubuntu.com/kinetic/current/kinetic-server-cloudimg-riscv64.img

kinetic-server-cloudimg-riscv64.raw:
	qemu-img convert kinetic-server-cloudimg-riscv64.img kinetic-server-cloudimg-riscv64.raw

prepare:
	ssh-keygen -t rsa -b 4096 -f id_rsa -P ''
	src/userdata.py -o cidata/user-data

login:
	ssh -v -i id-rsa user@localhost -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 8022
