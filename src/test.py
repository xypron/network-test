#!/usr/bin/python3
"""Run test"""

import argparse
import logging
import re
import subprocess
import sys
import yaml

class ProcessRunner:
    """Run process"""

    def __init__(self, step, expected):
        self.step = step
        self.logger = logging.getLogger('network-test')
        self.logger.info(step['launch'])
        self.proc = subprocess.Popen(step['launch'].split(),
            shell = False,
            stdin = subprocess.PIPE,
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE)
        if expected:
            items = expected
            if isinstance(items, str):
                items = [items]
            for item in items:
                self.wait_for_output(item)

    def wait_for_output(self, expected):
        """Wait for a specific regular expression being matched and output line"""
        regex = re.compile(expected)
        while True:
            if self.proc.poll() is not None:
                name = self.step['name']
                self.logger.error('%s ended prematurely', name)
                outs, errs = self.proc.communicate()
                if outs:
                    stdout = outs.decode('utf-8')
                    self.logger.info('stdout: %s', repr(stdout))
                if errs:
                    stderr = errs.decode('utf-8')
                    self.logger.info('stderr: %s', repr(stderr))
                assert False
            if (out := self.proc.stdout.readline()):
                out = out.decode('utf-8', errors="ignore")
                self.logger.info('stdout: %s', repr(out))
                if regex.search(out):
                    self.logger.info('reached \'%s\' in \'%s\'', expected, self.step['name'])
                    return
    def stop(self):
        """Stop process"""
        name = self.step['name']
        if self.proc.poll() is not None:
            self.logger.error('%s ended prematurely', name)
            assert False
        self.proc.kill()
        self.logger.info('\'%s\' stopped', name)

    def stop_qemu(self):
        """stop QEMU"""
        #self.proc.stdin.write(b'\x01x')
        #self.proc.stdin.flush()
        outs, errs = self.proc.communicate(b'\x01x', timeout=None)
        if outs:
            stdout = outs.decode('utf-8')
            self.logger.info('stdout: %s', repr(stdout))
        if errs:
            stderr = errs.decode('utf-8')
            self.logger.info('stderr: %s', repr(stderr))

class TestRunner:
    """Test runner"""

    def __init__(self, file_name, log_file):
        self.filename = {}
        self.log_file = log_file
        self.logger = logging.getLogger('network-test')
        self.setup_logger()

        self.logger.info(file_name)
        with open(file_name, "rt", encoding="utf-8") as file:
            text = file.read()
        self.logger.info(text)
        self.test = yaml.load(text, Loader=yaml.SafeLoader)
        self.running = {}

    def setup_logger(self):
        """Set up logger"""
        self.logger.setLevel(logging.DEBUG)

        # create log file handler
        if self.log_file:
            formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
            file_handler = logging.FileHandler(self.log_file)
            file_handler.setFormatter(formatter)
            file_handler.setLevel(logging.DEBUG)
            self.logger.addHandler(file_handler)

        # create console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        self.logger.addHandler(console_handler)

    def command(self, step):
        """execute a command"""
        command = step['command']
        self.logger.info(repr(command))
        process = subprocess.run(command, capture_output = True, shell = True, check = False)

        returncode = process.returncode
        stdout = process.stdout.decode('utf-8')
        stderr = process.stderr.decode('utf-8')

        self.logger.info('stdout: %s', repr(stdout))
        self.logger.info('stderr: %s', repr(stderr))

        if (step.get('ret', 0)) != returncode:
            self.logger.error('unexpected return code %d', returncode)
            assert False

        if 'expected' in step:
            items = step['expected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                regex = re.compile(item)
                if not regex.search(stdout):
                    self.logger.error('\'%s\' not found in \'%s\'', item, repr(stdout))
                    assert False
        if 'expected_stderr' in step:
            items = step['expected_stderr']
            if isinstance(items, str):
                items = [items]
            for item in items:
                regex = re.compile(item)
                if not regex.search(stderr):
                    self.logger.error('\'%s\' not found in \'%s\'', item, repr(stderr))
                    assert False
        if 'unexpected' in step:
            items = step['unexpected']
            if isinstance(items, str):
                items = [items]
            for item in items:
                regex = re.compile(item)
                if regex.search(stdout):
                    self.logger.error('\'%s\' found in \'%s\'', item, repr(stdout))
                    assert False
                if regex.search(stderr):
                    self.logger.error('\'%s\' found in \'%s\'', item, repr(stderr))
                    assert False

    def launch(self, step):
        """launch process"""
        if not 'name' in step:
            self.logger.error('need a name')
            assert False
        if (name := step['name']) in self.running:
            self.logger.error('A process with name \'%s\' is already running', name)
            assert False
        self.logger.info('launching \'%s\'', name)
        process = ProcessRunner(step, step.get('expected', None))
        self.running[name] = process

    def stop(self, step):
        """stop process"""
        name = step['stop']
        if not name in self.running:
            self.logger.error('A process with name \'%s\' not launched', name)
            assert False
        self.logger.info('stopping \'%s\'', name)
        proc = self.running[name]
        proc.stop()
        del self.running[name]

    def stop_qemu(self, step):
        """stop process"""
        name = step['stopqemu']
        if not name in self.running:
            self.logger.error('A process with name \'%s\' not launched', name)
            assert False
        self.logger.info('stopping QEMU \'%s\'', name)
        proc = self.running[name]
        proc.stop_qemu()
        del self.running[name]

    def execute_step(self, step):
        """execute step"""
        self.logger.info('executing \'%s\'', step.get('name'))
        if 'command' in step:
            self.command(step)
        elif 'launch' in step:
            self.launch(step)
        elif 'stop' in step:
            self.stop(step)
        elif 'stopqemu' in step:
            self.stop_qemu(step)
        else:
            self.logger.error('unknown step \'%s\'', step)

    def execute(self):
        """execute test script"""
        for step in self.test['steps']:
            try:
                self.execute_step(step)
            except AssertionError as exception:
                self.logger.error(exception)
                return 1
        return 0

def main():
    """Command line entry point"""
    parser = argparse.ArgumentParser(description='Test runner')
    parser.add_argument('-f', '--script', type=str, help='script file name', required=True)
    parser.add_argument('-l', '--log', type=str, help='log file name')
    args = parser.parse_args()
    test_runner = TestRunner(args.script, args.log)
    ret = 1
    try:
        ret = test_runner.execute()
    except KeyboardInterrupt:
        pass
    if args.log:
        print(f'The log is available in \'{args.log}\'.')
    sys.exit(ret)

if __name__ == '__main__':
    main()
