id_rsa:
	ssh-keygen -t rsa -b 4096 -N '' -f id_rsa

cidata-x86.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data -p grub-efi
	mkisofs -J -V cidata -o cidata-x86.iso cidata/

cidata-riscv64.iso: id_rsa
	mkdir -p cidata/
	echo instance-id: $$(uuidgen) > cidata/meta-data
	src/userdata.py -o cidata/user-data
	mkisofs -J -V cidata -o cidata-risc64.iso cidata/

amd64.img:
	cp kinetic-server-cloudimg-amd64.raw amd64.img
	qemu-img resize amd64.img +8G

riscv64.img:
	cp kinetic-server-cloudimg-risv64.raw riscv64.img
	qemu-img resize amd64.img +8G

x86_VARS.fd:
	dd if=/dev/zero of=x86_VARS.fd bs=540672 count=1

x86: cidata-x86.iso amd64.img x86_VARS.fd
	cp kinetic-server-cloudimg-amd64.raw /tmp/amd64.img
	qemu-system-x86_64 \
	-M q35 -accel kvm -m 16G -smp 8 \
	-nographic \
	-drive file=amd64.img,format=raw,if=virtio \
	-drive file=cidata-x86.iso,format=raw,if=virtio \
	-global driver=cfi.pflash01,property=secure,value=off \
	-drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
	-drive if=pflash,format=raw,unit=1,file=x86_VARS.fd \
	-device virtio-net-pci,netdev=eth0 \
	-netdev user,id=eth0,hostfwd=tcp::8022-:22

rv: cidata-riscv.iso
	src/userdata.py -o cidata/user-data -r -p 'grub-efi qemu-system-misc u-boot-qemu opensbi linux-image-starfive'
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
	-drive file=cidata-riscv64.iso,format=raw,if=virtio \
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
