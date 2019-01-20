#!/usr/bin/env bash

# Number of workers
N_WORKERS=1
# Number of controllers. Use 2 and expect to see split-brain issue ;)
N_CONTROLLERS=1
# Memory for worker instance. Can use lower size.
MEM_WORKER="1024"
# Memory for controllers. 1g is recommened.
MEM_CONTROLLER="1024"
# Our haproxy and adhoc dns resolver. 256mb is just enough.
MEM_LB="256"

# CoreDNS loop detecting, https://coredns.io/plugins/loop/
# If you are using localhost/127.0.0.1 as dns resolver
# in your (VirtualBox) host system, please change to empty string.
COREDNS_LOOP=""
# Otherwise, please use 'loop
#COREDNS_LOOP="loop"
