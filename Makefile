
.PHONY: vfio

export PATH:=$(PATH):/usr/share/openvswitch/scripts
export DB_SOCK=/var/run/openvswitch/db.sock

vfio:
	# Prepare for using DPDK
	sudo modprobe vfio enable_unsafe_noiommu_mode=1
	sudo modprobe vfio-pci
	echo 1 | sudo tee -a /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
	sudo dpdk-devbind.py --bind=vfio-pci 0000:00:03.0
	sudo dpdk-devbind.py --status

network:
	ovs-ctl --system-id=random start
	ovs-vsctl add-br br01
	ifconfig br01 up
	ovs-vsctl add-port <name> eth0
	ifconfig eth 0
	dhclient <name>

foo:
	sudo update-alternatives --set ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk
	sudo ovs-vsctl del-br ovsdpdkbr0 || /bin/true
	sudo ovs-vsctl add-br ovsdpdkbr0 -- set bridge ovsdpdkbr0 datapath_type=netdev
	sudo ovs-vsctl add-port ovsdpdkbr0 dpdk0 -- set Interface dpdk0 type=dpdk "options:dpdk-devargs=0000:00:03.0"
