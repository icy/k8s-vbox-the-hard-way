## Bootstrap a k8s cluster the hardway with VirtualBox

Scripts that follow
  [k8s the hardway](https://github.com/kelseyhightower/kubernetes-the-hard-way)
to bootstrap a k8s cluster in VirtualBox environment with Vagrant.
This scripts only works on Linux / MacOS 64-bit machines.
New cluster has the following components

    Bundle version:           v1.12.0
    Helm version:             v2.12.2
    Etcd version:             v3.3.9
    Coredns version:          1.2.2
    Runc version:             v1.0.0-rc6
    CNI plugin version:       v0.7.4
    Containerd version:       v1.2.2

Table of contents

* [Getting started](#getting-started)
  * [Installing basic tools](#installing-basic-tools)
  * [Bootstrapping new cluster](#bootstrapping-new-cluster)
  * [Testing](#testing)
    * [The very basic test](#the-very-basic-test)
    * [Running smoke tests](#running-smoke-tests)
    * [Testing with Helm](#testing-with-helm)
  * [Debugging](#debugging)
  * [Known issues](#known-issues)
  * [Tearing down](#tearing-down)
* [In-depth docs, details and customizations](#in-depth-docs-details-and-customizations)
  * [List of all steps to bootstrap new cluster](#list-of-all-steps-to-bootstrap-new-cluster)
* [Acknowledgements](#acknowledgements)

## Getting started

### Installing basic tools

On Linux:

* VirtualBox (`pacman -S virtualbox`). Also make sure the user that
  executes this script belongs to the group `vboxusers`.
* Vagrant (`pacman -S vagrant`). Pre download a box for launching new machines

      vagrant box add ubuntu/bionic64

* coreutils and `getttext` packages (`pacman -S gettext`)

On MacOS:

    brew cask install virtualbox
    brew cask install vagrant
    brew install coreutils
    brew install gnu-sed
    brew install gettext
    brew link --force gettext

The script download and store the following tools in local cache directory:

* [Cloudflare PKI toolkit](https://github.com/cloudflare/cfssl)
* [`kubectl` command line](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-using-curl)
* [`helm` command line](https://helm.sh/docs/using_helm/#install-kubernetes-or-have-access-to-a-cluster)

### Bootstrapping new cluster

Edit some basic settings in `./etc/custom.env.sh` and start the cluster.
A sample file can be found here [etc/example_custom.env.sh](./etc/example_custom.env.sh).
You can optionally add the `./bin/` directory (which contains `hisk8s.sh` script)
to your binaries search path.

    $ # export PATH=$PATH:$(pwd -P)/bin/  # Optionally

    $ hisk8s.sh                           # Getting some helps
    $ hisk8s.sh _env                      # Print basic information
    $ hisk8s.sh _test                     # Create new cluster
    $ hisk8s.sh _kubectl cluster-info     # Get cluster info.

    Kubernetes master is running at https://127.0.0.1:6443
    CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
    To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

**Notes:** During the bootstrapping phase, the command `hisk8s.sh _test`
may fail at some step. You can start from the last known step:

    $ hisk8s.sh _test
    # <snip>
    :: Executing _some_internal_step
    # <snip>
    :: ==========================
    :: Last method: _some_internal_step
    :: Last method return code: unknown

You can try to get around the issue (or do nothing) and retry

      $ hisk8s.sh _some_internal_step

If everything goes well you can process any steps following this one.
See a list of all steps as below:

      $ hisk8s.sh _steps

### Testing

#### The very basic test

When a cluster starts, it also starts some basic pods in `kube-system`
namespace. The cluster is healthy if these pods are running well

    $ hisk8s.sh _kubectl get pods -n kube-system
    :: Custom environment file not found: /home/testing/src/k8s-vbox-the-hard-way/etc//custom.env.sh
    NAME                       READY   STATUS    RESTARTS   AGE
    coredns-699f8ddd77-7kwtt   1/1     Running   0          31s
    coredns-699f8ddd77-xstzw   1/1     Running   0          31s

If you always see `ContainerCreating` in the command's output there must
be something wrong. Try to log in to any worker node to debug. However,
try to wait a few seconds first;)

#### Running smoke tests

You may want to skip to the next section instead.

These tests are inspired by the original `k8s the hard way`; you have
to clean up the pods and services after the tests.

    $ hisk8s.sh _smoke_tests
    $ hisk8s.sh _smoke_test_deploy_app

`kubectl` configuration will be stored under `./etc/.kube/config`.
You can execute the tool via the wrapper, for examples:

    $ hisk8s.sh _kubectl get nodes
    NAME         STATUS   ROLES    AGE    VERSION
    worker-141   Ready    <none>   100s   v1.12.0

(You can also use the shortcut `./bin/_kubectl`)

#### Testing with Helm

If you haven't installed `helm`, you can download them with `_wget_hem`
then optionally move the binary from `caches/` to your search path.
`hisk8s.sh` will search `helm` in `caches/` after giving up finding
in your default binaries search path.

    $ hisk8s.sh _wget_helm # optionally, binary saved in caches/
    $ hisk8s.sh _helm_init
    $ hisk8s.sh _helm_test

After this command, you would get the following error

    Error: could not find a ready tiller pod

That's because there are some delays. Please wait a few seconds and type
the following command

    $ hisk8s.sh _kubectl get pods -n kube-system

to see that your `tiller-deploy-*` pods are running well. Then you try
to execute `_helm_test` again

    $ hisk8s.sh _kubectl get pods -n kube-system|grep tiller
    tiller-deploy-865b88d89-xf2s4      1/1     Running   0          4m10s
    $ hisk8s.sh _helm_test
    $ hisk8s.sh _helm list
    NAME    REVISION        UPDATED                         STATUS          CHART           APP VERSION     NAMESPACE
    empty   1               Sun Jan 20 14:39:19 2019        DEPLOYED        empty-0.1.0     1.0             default
    traefik 1               Sun Jan 20 14:39:19 2019        DEPLOYED        traefik-0.1.0   1.0             default

If you open a sock proxy through the load balancer, you can access these services

    $ _ssh lb100 -D 10000 -fN

Now reconfigure your browser to use the socks5 proxy (host: `localhost`, port: `10000`),
and input the following address in the newly configured browser:

    http://empty.k8s/
    http://traefik.k8s/

You can also access these addresses in the load balancer's shell:

    $ _ssh 100
    vagrant@lb-100:~$ curl http://empty.k8s
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    <snip>

The cluster is ready for you.

### Debugging

To enter a node, use the wrapper script:

    $ hisk8s.sh _ssh_list
    $ hisk8s.sh _ssh 111

You can also use different aliases provided in the output of `_ssh_list`.
For worker nodes, most critical logs are sent to journald daemon:

    $ sudo journalctl -f

would give you an idea of what's happening in the system.

### Known issues

1. `kube proxy` may not work, as the cluster (aka virtualbox) network
   is not reachable from your laptop (where `kubectl` installed.)
1. The script reports some vagrant node is not running: Please try with
   the commmand `VBoxManage list runningvms`. If you see empty output,
   there would be a problem with vbox driver. Please reboot your machine
   (the easy way) or reload your vbox drivers (the hard way).
1. `Failed to restart networking.service`: Never mind, the script will
    try another way to reload virtual machine network service.

### Tearing down

    $ hisk8s.sh _vagrant destroy -f

Except your custom environment `etc/custom.env.sh` and caches directory,
you can delete all newly created files

    $ cp etc/custom.env.sh ./my.custom.env.sh
    $ rm -rf etc/ ca/
    $ git reset --hard # Restore the original scripts / configurations

**Important notes**:
The script is stateless and it doesn't know if you have decreased the
number of workers/controllers. If you change `etc/custom.env.sh`
the script probably can't help to destroy all nodes. If that's the case,
the best way is to restore the high number(s) and execute

    $ hisk8s.sh _vagrant destroy -f

because deleting nodes from `VirtualBox` doesn't help to remove some
port-forwarding settings.

## In-depth docs, details and customizations

### List of all steps to bootstrap new cluster

The list of all steps as in

  https://github.com/kelseyhightower/kubernetes-the-hard-way#labs

can be seen by using the `_steps` method.
This prints the definition of the `_test` method.

    $ ./bin/hisk8s.sh _steps
    _test ()
    {
        set -xe;
        __execute __require;
        __execute _vagrant up;
        __execute _k8s_bootstrapping_ca;
        __execute _k8s_bootstrapping_lb_vboxdns;
        __execute _k8s_bootstrapping_lb_haproxy;
        __execute _k8s_bootstrapping_etcd;
        __execute _k8s_encryption_key_gen;
        __execute _k8s_bootstrapping_control_plane;
        __execute _k8s_bootstrapping_worker;
        __execute _k8s_worker_routing;
        __execute _k8s_bootstrapping_kubectl_config;
        __execute _k8s_bootstrapping_coredns;
        __execute _k8s_bootstrapping_rbac_cluster_role;
        set +x;
        _welcome
    }

## Acknowledgements

* `@hungdo` (Telegram) for testing and reporting the issue
  (9b2391d1fa41a985acc158c73a686a4485b25bf0)
* `@buomQ` (Telegram) for testing and reporting some issue
  (network provisioning, helm) on MacOS systems.
