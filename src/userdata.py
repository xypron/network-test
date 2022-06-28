#!/usr/bin/python3

import argparse
from pathlib import Path
import yaml

class UserData:
    def __init__(self, hostName, sshKeyFile, user):
        self.data = {};
        self.data['hostname'] = hostName
        self.data['manage_etc_hosts'] = 'localhost'
        self.data['users'] = [{
            'name' : user,
            'shell' : '/bin/bash',
            'groups' : 'dialout, kvm, sudo',
            'sudo' : 'ALL=(ALL) NOPASSWD:ALL',
            'ssh_authorized_keys' : self.readKeyFile(sshKeyFile)
        }]

    def dump(self, fileName):
        with open(fileName, 'w', encoding='utf-8') as file:
            file.write('#cloud-config\n')
            file.write(yaml.dump(self.data))

    def readKeyFile(self, fileName):
        with open(fileName, 'r', encoding='utf-8') as file:
            return file.read().strip().splitlines()

def main():
    """Command line entry point"""
    parser = argparse.ArgumentParser(description='Create cloud-init user-data')
    parser.add_argument('-n', '--hostname', default='unknown', type=str, help='hostname')
    parser.add_argument('-o', '--filename', default='user-data', type=str, help='file name')
    parser.add_argument('-s', '--sshkeyfile', default='id_rsa.pub', help='ssh key file')
    parser.add_argument('-u', '--user', default='user', help='user name')
    args = parser.parse_args()
    ud = UserData(args.hostname, args.sshkeyfile, args.user)
    ud.dump(args.filename)

if __name__ == '__main__':
    main()
