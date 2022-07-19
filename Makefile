all:
	# Client
	# ======
	#
	sudo ifconfig enp0s3 down || true
	sudo ifconfig enp0s3 10.0.200.202/24 up
	# Connect to iSCSI target
	sudo iscsiadm -m discovery -t sendtargets -p 10.0.200.201
	sudo iscsiadm -m node --logout || true
	sudo iscsiadm -m node --login
	# Show devices
	lsblk
	# Tune
	echo none | sudo tee /sys/block/sda/queue/scheduler
	# echo none | sudo tee /sys/block/sdb/queue/scheduler
	# Copy data
	sudo dd if=/dev/sda of=/dev/null bs=1M iflag=direct
