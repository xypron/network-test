Test DPDK, SPDK, OpenVSwitch
============================

This test is used to test the packages

* Data Plane Development Kit (DPDK)
* Open vSwitch
* Storage Performance Development Kit (SPDK)

on the x86_64 and RISC-V architectures.

The packages are provided in the following Ubuntu PPA repositories:

* ppa:ubuntu-risc-v-team/release
* ppa:ubuntu-risc-v-team/develop

Test scripts
------------

The test steps are described in YAML files (amd64.yaml, riscv64.yaml) and run
via src/test.py.

The generic structure of a test script is

.. code-block:: yaml

    ---
    steps:

      - name: step 1
        command:
          echo -n 'Hello' && echo ' world'
        expected: world

      - name: step 2
        command:

The following types of steps are supported:

command
  Execute a command using subprocess.
  The step completes when the command is completed.
  The stdout and stderr output is recorded.

  The step takes the following arguments:

  name
    identifier used for logging

  command
    string with command to execute

  expected
    regular expression to be matched by stdout output
    or an array of such expressions

  expected_stderr
    regular expression to be matched by stderr output
    or an array of such expressions

  ret
    expected return code, defaults to 0

launch
  Execute a command using subprocess.
  The step completes when the last ``expected`` regular expression is met.
  The subprocess lives on and is not expected to stop
  The stdout and stderr output is recorded.

  The step takes the following arguments:

  name
    identifier used for logging and stopping the process

  launch
    string with command to execute

  expected
    regular expression to be matched by stdout output
    or an array of such expressions.
    The step completes when the last regular expression is met in the sequence
    of occurance in the array.

stop
  Stop a launched subprocess.

  The step takes the following arguments:

  name
    identifier used for logging

  stop
    The value of name used in the launch stop.

stopqemu
  Stop a launched subprocess running QEMU.
  QEMU is stopped by sending <CTRL-A><x>.

  The step takes the following arguments:

  name
    identifier used for logging

  stopqemu
    The value of name used in the launch stop.

Running a test
--------------

Test are executed using src/test.py which takes the following arguments

::

   test.py [-h] -f SCRIPT [-l LOG]

\-h, --help
    show help message and exit

\-f SCRIPT, --script SCRIPT
    script file name

\-l LOG, --log LOG
    log file name

test.sh is supplied as wrapper around src/test.py.
The first argument is the test script.
The second optional argument is the name of the log file.
If none is provided, it is autogenerated.

.. code-block:: bash

    ./test.sh x86.yaml

A successful test ends with a message

::

    All test steps executed successfully

and return code 0.

Test scenario
-------------

A first QEMU virtual machine is created. Open VSwitch runs in this machine.
In side this virtual machine two further virtual machines are created.
The first of these runs the SPDK iSCSI target. The second one runs an iSCSI
client using Open-iSCSI::

    +--------------------------------------------------------------------------+
    |                                    :                                     |
    |   Host                             :                                     |
    |             :8x21                  :                  :8x31    :8x11     |
    |               :                    :                    :        :       |
    |  +--------------------------------------------------------------------+  |
    |  |            :                    :                    :        :    |  |
    |  | Main VM    :                    :                    :       :22   |  |
    |  |            :   +---------------------------------+   :             |  |
    |  |            :   |                :                |   :             |  |
    |  |            :   |              dpdk0              |   :             |  |
    |  |            :   |                                 |   :             |  |
    |  |            :   |          Open VSwitch           |   :             |  |
    |  |            :   |                                 |   :             |  |
    |  |            :   |  vport1                 vport2  |   :             |  |
    |  |            :   |    :                       :    |   :             |  |
    |  |            :   +---------------------------------+   :             |  |
    |  |            :        :                       :        :             |  |
    |  |            :        :                       :        :             |  |
    |  |  +-----------------------------+  +-----------------------------+  |  |
    |  |  | VM 1    :        :          |  |         :        :     VM 2 |  |  |
    |  |  |        :22   10.0.2.201     |  |    10.0.2.202   :22         |  |  |
    |  |  |                             |  |                             |  |  |
    |  |  +-----------------------------+  +-----------------------------+  |  |
    |  |                                                                    |  |
    |  +--------------------------------------------------------------------+  |
    |                                                                          |
    +--------------------------------------------------------------------------+

Each virtual machine has two emulated network cards. One is used for SSH the
other is available for Open VSwitch.

The ssh ports of all virtual machines are forwarded to the host. Different port
numbers are used for forwarding for each tested architecture.

Code
----

src/test.py
    This is the test runner script.

userdata.py
    This helper script creates the user-data file for cloud-init of the main
    virtual machine.

clientdata.py
    This helper script creates the user-data file for cloud-init of the
    child virtual machines.
