#!/bin/bash

if [ $# -ge 2 ]; then
	log=$2
else
	log=$(mktemp nwt-XXXXXX.log)
	echo "logging to $log"
fi

python src/test.py -f $1 -l $log
