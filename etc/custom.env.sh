#!/usr/bin/env bash

# Number of workers
N_WORKERS=1
# Number of controllers. Use 2 and expect to see split-brain issue ;)
N_CONTROLLERS=1
# Memory for worker instance. Can use lower size.
MEM_WORKER="2024"
# Memory for controllers. 1g is recommened.
MEM_CONTROLLER="1024"
# Our haproxy and adhoc dns resolver. 256mb is just enough.
MEM_LB="256"
