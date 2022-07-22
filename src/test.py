#!/usr/bin/python3
"""Run test"""

import argparse
import re
import subprocess
import yaml

class ProcessRunner:
    """Run process"""

    def __init__(self, step, expected):
        self.step = step
        self.proc = subprocess.Popen(step['launch'],
            shell = True,
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE)
        if expected:
            self.wait_for_output(expected)

    def wait_for_output(self, expected):
        """Wait for a specific regular expression being matched and output line"""
        r = re.compile(expected)
        while True:
            if self.proc.poll() is not None:
                id = self.step['name']
                print(f'{id} ended prematurely')
                assert False
            if (out := self.proc.stdout.readline()):
                out = out.decode('utf-8', errors="ignore")
                print(out, end='')
                if r.search(out):
                    return

    def stop(self):
        """Stop process"""
        if self.proc.poll() is not None:
            id = self.step['name']
            print(f'{id} ended prematurely')
            assert False
        self.proc.kill()
        id = self.step['name']
        print(f"'{id}' stopped")

class TestRunner:
    """Test runner"""

    def __init__(self, file_name):
        self.filename = {}
        print(file_name)
        with open(file_name, "rt", encoding="utf-8") as f:
            text = f.read()
        print(text)
        self.test = yaml.load(text, Loader=yaml.SafeLoader)
        self.running = {}

    def command(self, step):
        command = step['command']
        print(repr(command))
        process = subprocess.run(command, capture_output = True, shell = True)

        returncode = process.returncode
        stdout = process.stdout.decode('utf-8')
        stderr = process.stderr.decode('utf-8')

        print(f"stdout: {repr(stdout)}")
        print(f"stderr: {repr(stderr)}")

        expected_returncode = step.get('ret', 0)
        if expected_returncode != returncode:
            print(f'unexpected return code {returncode}')
            print(f'stderr {repr(stderr)}')
            assert False
        assert(expected_returncode == process.returncode)

        if 'expected' in step:
            items = step['expected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                r = re.compile(item)
                if not r.search(stdout):
                    print(f"'{item}' not found in {repr(stdout)}")
                    assert False
        if 'unexpected' in step:
            items = step['unexpected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                r = re.compile(item)
                if r.search(stdout):
                    print(f"'{item}' found in {repr(stdout)}")
                    assert False
                if r.search(stderr):
                    print(f"'{item}' found in {repr(stderr)}")
                    assert False

    def launch(self, step):
        if not 'name' in step:
            print('need a name')
            assert False
        id = step['name']
        if id in self.running:
            print(f'A process with id {id} is already running')
            assert False
        print(f"launching '{id}'")
        process = ProcessRunner(step, step.get('expected', None))
        self.running[id] = process
        pass

    def stop(self, step):
        id = step['stop']
        if not id in self.running:
            print(f'A process with id {id} is not launched')
            assert False
        print(f"stopping '{id}'")
        proc = self.running[id]
        proc.stop()
        del self.running[id]
        pass

    def execute_step(self, step):
        print(f"executing '{step.get('name')}'")
        if 'command' in step:
            self.command(step)
        if 'launch' in step:
            self.launch(step)
        if 'stop' in step:
            self.stop(step)

    def execute(self):
        for step in self.test['steps']:
            self.execute_step(step)

def main():
    """Command line entry point"""
    parser = argparse.ArgumentParser(description='Create cloud-init user-data')
    parser.add_argument('-f', '--filename', type=str, help='file name')
    args = parser.parse_args()
    test_runner = TestRunner(args.filename)
    test_runner.execute()

if __name__ == '__main__':
    main()
