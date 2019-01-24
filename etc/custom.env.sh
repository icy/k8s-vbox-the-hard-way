#!/usr/bin/env bash

# Exit the script immediately if any error occurs.
set -e

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
VAGRANT_PARALLEL=0 # Disable

# List of port for automatic mapping/forwarding from Load balancer
# to on workers. This is useful when working witl NodePort services.
# You can also add any port to `etc/haproxy/ports`.
#
# When you update this variable please execute the step `_lb_update`
# by invoking `hisk8s.sh _lb_update`. Please note `_lb_update` also
# sets up VirtualBox port forwarding for the load balancer accordingly.
HAPROXY_AUTO_PORTS=""
