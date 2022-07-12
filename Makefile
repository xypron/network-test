vfio:
	# Prepare for using DPDK
	sudo modprobe vfio enable_unsafe_noiommu_mode=1
	sudo modprobe vfio-pci
	echo 1 | sudo tee -a /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
	sudo dpdk-devbind.py --bind=vfio-pci 0000:00:03.0
	sudo dpdk-devbind.py --status

network: vfio
	echo network


spdk:
	sudo iscsi_tgt --no-pci &
	sudo /usr/share/scripts/spdk/rpc.py bdev_malloc_create -b Malloc0 64 512
	sudo /usr/share/scripts/spdk/rpc.py bdev_malloc_create -b Malloc1 64 512
