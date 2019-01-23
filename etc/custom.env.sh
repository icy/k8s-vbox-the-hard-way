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

# Enable to invoke vagrant commands in parallel (very fast!!!)
#
# Use this feature at your own risk: The main script will not check if
# there is any errors from vagrant sub-proceses. Moreover, all machines
# would be started at the same time so if the number of nodes is greater
# than number of cores you would hear noisy sound from PC fan ;)
#
# It's recommended that you start with 0 in the very first tries
# (e.g, with lower number of workers/controllers) and then
# move fast later.
#
# FIXME: We will ensure parallel feature work persistently.
VAGRANT_PARALLEL=0
