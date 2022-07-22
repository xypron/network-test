#!/usr/bin/python3
"""Run test"""

import argparse
from pprint import pprint
import re
import subprocess
import yaml

class TestRunner:
    """Test runner"""

    def __init__(self, file_name):
        self.filename = {}
        print(file_name)
        with open(file_name, "rt", encoding="utf-8") as f:
            text = f.read()
        print(text)
        self.test = yaml.load(text, Loader=yaml.SafeLoader)

    def execute_command(self, step):
        command = step['command']
        print(repr(command))
        command = ['bash', '-c', command]
        process = subprocess.run(command, capture_output = True)

        returncode = process.returncode
        stdout = process.stdout.decode('utf-8')
        stderr = process.stderr.decode('utf-8')

        print(f"stdout: {repr(stdout)}");
        print(f"stderr: {repr(stderr)}");

        expected_returncode = step.get('ret', 0)
        if expected_returncode != returncode:
            print(f'unexpected return code {returncode}')
            print(f'stderr {repr(stderr)}');
            assert False
        assert(expected_returncode == process.returncode)

        if 'expected' in step:
            items = step['expected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                r = re.compile(item)
                if not r.search(stdout):
                    print(f"'{item}' not found in {repr(stdout)}");
                    assert(False)
        if 'unexpected' in step:
            items = step['unexpected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                r = re.compile(item)
                if r.search(stdout):
                    print(f"'{item}' found in {repr(stdout)}");
                    assert(False)
                if r.search(stderr):
                    print(f"'{item}' found in {repr(stderr)}");
                    assert(False)

    def execute_step(self, step):
        print(f"executing '{step.get('name')}'")
        if step['command']:
            self.execute_command(step)

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
