#!/usr/bin/python3
"""Generate cloud-init user-data"""

import argparse
import yaml

class UserData:
    """Generate cloud-init user-data"""

    def __init__(self, host_name, ssh_key_file, user):
        self.data = {}
        self.data['hostname'] = host_name
        self.data['manage_etc_hosts'] = 'localhost'
        self.data['apt'] = {'sources' : {
            'rvrelease' : { 'source' : 'ppa:ubuntu-risc-v-team/release' },
            'rvdevelop' : { 'source' : 'ppa:ubuntu-risc-v-team/develop' }
        }}
        self.data['users'] = [{
            'name' : user,
            'shell' : '/bin/bash',
            'groups' : 'dialout, kvm, sudo',
            'sudo' : 'ALL=(ALL) NOPASSWD:ALL',
            'ssh_authorized_keys' : self.read_key_file(ssh_key_file)
        }]

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
    parser.add_argument('-s', '--sshkeyfile', default='id_rsa.pub', help='ssh key file')
    parser.add_argument('-u', '--user', default='user', help='user name')
    args = parser.parse_args()
    user_data = UserData(args.hostname, args.sshkeyfile, args.user)
    user_data.dump(args.filename)

if __name__ == '__main__':
    main()
