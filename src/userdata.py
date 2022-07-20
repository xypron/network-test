#!/usr/bin/python3
"""Generate cloud-init user-data"""

import argparse
import yaml

class UserData:
    """Generate cloud-init user-data"""

    def __init__(self, host_name, ssh_key_file, user, packages = ''):
        self.data = {}
        self.data['hostname'] = host_name
        self.data['manage_etc_hosts'] = 'localhost'
        self.data['apt'] = {'sources' : {
            'rvrelease' : {
                'source' : 'ppa:ubuntu-risc-v-team/release',
                'keyid' : '52663FF2DFDC39CA',
                'keyserver' : 'keyserver.ubuntu.com'
            },
            'rvdevelop' : {
                'source' : 'ppa:ubuntu-risc-v-team/develop',
                'keyid' : '52663FF2DFDC39CA',
                'keyserver' : 'keyserver.ubuntu.com'
            },
            'kernel' : {
                'source' : 'ppa:canonical-kernel-team/ppa',
                'keyid' : '0856F197B892ACEA',
                'keyserver' : 'keyserver.ubuntu.com'
            }
        }}
        self.data['users'] = [{
            'name' : user,
            'shell' : '/bin/bash',
            'groups' : 'dialout, kvm, sudo',
            'sudo' : 'ALL=(ALL) NOPASSWD:ALL',
            'ssh_authorized_keys' : self.read_key_file(ssh_key_file)
        }]
        self.data['packages'] = packages.split()
        self.data['package_update'] = True
        self.data['runcmd'] = [
                'mount /dev/vdb /mnt -o ro',
                'test -f /mnt/*.deb && dpkg -i /mnt/*.deb',
                'umount /dev/vdb',
                'systemctl start dpdk',
                'systemctl start ovsdb-server.service',
                'ovs-vsctl set Open_vSwitch . "other_config:dpdk-init=true"',
                'ovs-vsctl set Open_vSwitch . "other_config:dpdk-alloc-mem=1024"',
                'systemctl stop ovs-vswitchd.service',
                'update-alternatives --set ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk',
                'addgroup --system hugepage',
                'addgroup --system unpriv_ping',
                'adduser user hugepage',
                'adduser user unpriv_ping',
                'grep hugepage /etc/group | sed -e \'s/^[^[:digit:]]*\\([[:digit:]]*\\).*/hugepagetlbfs \\/dev\\/hugepages hugetlbfs gid=\\1,mode=775/g\' >> /etc/fstab',
                'grep unpriv_ping /etc/group | sed -e \'s/^[^[:digit:]]*\\([[:digit:]]*\\).*/net.ipv4.ping_group_range = \\1 \\1/g\' > /etc/sysctl.d/99-qemu.conf',
                'grub-install',
                'sed -i -e \'s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="default_hugepagesz=2M hugepagesz=2M hugepages=5120"/g\' /etc/default/grub',
                'update-grub',
                'reboot'
        ]

    def dump(self, file_name):
        """Writes the user-data yaml file"""

        with open(file_name, 'w', encoding='utf-8') as file:
            file.write('#cloud-config\n')
            file.write(yaml.dump(self.data))

    @staticmethod
    def read_key_file(file_name):
        """Reads the SSH key file"""

        with open(file_name, 'r', encoding='utf-8') as file:
            return file.read().strip().splitlines()

def main():
    """Command line entry point"""
    parser = argparse.ArgumentParser(description='Create cloud-init user-data')
    parser.add_argument('-n', '--hostname', default='unknown', type=str, help='hostname')
    parser.add_argument('-o', '--filename', default='user-data', type=str, help='file name')
    parser.add_argument('-p', '--packages', default='user-data', type=str, help='whitespace separated list of packages')
    parser.add_argument('-s', '--sshkeyfile', default='id_rsa.pub', help='ssh key file')
    parser.add_argument('-u', '--user', default='user', help='user name')
    args = parser.parse_args()
    user_data = UserData(args.hostname, args.sshkeyfile, args.user, args.packages)
    user_data.dump(args.filename)

if __name__ == '__main__':
    main()
