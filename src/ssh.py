#!/usr/bin/python3
"""Connect via SSH"""

from colors import red, green
import paramiko

class SshRunner:

    def __init__(self, port):
        self.client = ssh_client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.client.WarningPolicy)
        self.client.connect(
            hostname = 'localhost',
            username = 'user',
            key_filename = 'id_rsa',
            port = port)

    def exec(self, command):
        """Execute command"""
        transport = self.client.get_transport()
        channel = transport.open_channel(kind = 'session')
        channel.exec_command(command)
        while True:
            while channel.recv_stderr_ready():
                err = channel.recv_stderr(1000000)
                print(red(err.decode('utf-8')))

            while channel.recv_ready():
                out = channel.recv(1000000)
                print(out.decode('utf-8'))

            if channel.exit_status_ready():
                ret = channel.recv_exit_status()
                channel.close()
                print(green(f'status = {ret}'))
                return ret

    def stop(self):
        """Stop ssh connection"""
        self.client.close()

def main():
    """Command line entry point"""
    ssh = SshRunner(8022)
    status = ssh.exec('ls voodoo')
    status = ssh.exec('ping -c 4 8.8.8.8')
    ssh.stop()

if __name__ == '__main__':
    main()
