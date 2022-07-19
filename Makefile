all:
	# Target
	# ======
	#
	# initialize network
	sudo ifconfig enp0s3 down
	sudo ifconfig enp0s3 10.0.200.201/24 up
	# Start iSCSI target application
	sudo iscsi_tgt &
	# Create volumes
	sudo modprobe vfio enable_unsafe_noiommu_mode=1
	sudo modprobe vfio-pci
	sudo echo 1 | sudo tee -a /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
	sudo /usr/share/spdk/scripts/setup.sh
	sudo /usr/share/spdk/scripts/rpc.py bdev_nvme_attach_controller -b NVMe1 -t PCIe -a 0000:00:04.0
	# Create new portal group with id 1, and address 10.0.200.201:3260:
	sudo /usr/share/spdk/scripts/rpc.py iscsi_create_portal_group 1 10.0.200.201:3260
	# Create initiator group with id 2 to accept any connection from 10.0.200.0/24:
	sudo /usr/share/spdk/scripts/rpc.py iscsi_create_initiator_group 2 ANY 10.0.200.0/24
	# Create target with block devices LUN0 (NVME1) with name
	# "disk1" alias "Data Disk1" using portal group 1 and initiator group 2.
	sudo /usr/share/spdk/scripts/rpc.py iscsi_create_target_node disk1 "Data Disk1" "NVMe1n1:0" 1:2 64 -d
