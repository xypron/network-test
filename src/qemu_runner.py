#!/usr/bin/python3
"""Run test"""

import re
import subprocess
import time

STOPPED = 1
STARTED = 2
READY = 3

class QemuRunner():
    """Run QEMU"""

    def __init__(self, command, ready = None):
        self.__state = STOPPED
        self.__ready = ready
        self.__proc = subprocess.Popen(command,
            shell = False,
            stdin = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE)
        self.__state = STARTED
        time.sleep(1)
        if self.__proc.poll():
            self.__show_output()
            raise subprocess.SubprocessError
        self.__wait_for_ready()

    def get_status(self):
        """Get the status of the virtual machine"""
        return self.__state

    def __show_output(self):
        """Wait for process to complete and print output"""

        out, err = self.__proc.communicate()
        if out:
            print(out.decode("utf-8"))
        if err:
            print(err.decode("utf-8"))

    def wait_for_output(self, expected):
        """Wait for a specific regular expression being matched and output line"""

        while True:
            if (out := self.__proc.stdout.readline()):
                out = out.decode("utf-8")
                print(out, end='')
                if re.search(expected, out):
                    return

    def __wait_for_ready(self):
        """Wait for output indicating ready state"""

        if self.__ready:
            self.wait_for_output(self.__ready)

        self.__state = READY

    def stop(self):
        """Stop virtual machine"""

        self.__proc.kill()

def main():
    """Command line entry point"""
    qemu = QemuRunner([
        "qemu-system-x86_64",
        "-M", "q35", "-accel", "kvm", "-m", "16G", "-smp", "8",
        "-nographic",
        "-drive", "file=/tmp/amd64.img,format=raw,if=virtio",
        "-drive", "file=cidata.iso,format=raw,if=virtio",
        "-device", "virtio-net-pci,netdev=eth0",
        "-netdev", "user,id=eth0,hostfwd=tcp::8022-:22"],
        r'Cloud-init.*finished')
    print("main: READY")
    qemu.stop()

if __name__ == '__main__':
    main()
