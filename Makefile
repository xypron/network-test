
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
