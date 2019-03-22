## Bootstrap a k8s cluster the hardway with VirtualBox

Scripts that follow
  [k8s the hardway](https://github.com/kelseyhightower/kubernetes-the-hard-way)
to bootstrap a k8s cluster in VirtualBox environment with Vagrant.
This scripts only works on Linux 64-bit machines.
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
    * [Running smoke tests](#running-smoke-tests)
    * [Testing with Helm](#testing-with-helm)
  * [Debugging](#debugging)
  * [Known issues](#known-issues)
  * [Tearing down](#tearing-down)
* [In-depth docs, details and customizations](#in-depth-docs-details-and-customizations)
  * [List of all steps to bootstrap new cluster](#list-of-all-steps-to-bootstrap-new-cluster)
* [Acknowledgements](#Acknowledgements)

## Getting started

### Installing basic tools

* VirtualBox (`pacman -S virtualbox`)
* Vagrant (`pacman -S vagrant`)
* https://github.com/cloudflare/cfssl (Please install all tools with
  `go get -u github.com/cloudflare/cfssl/cmd/...` and modify your `PATH`
  environment variable to recognize these new tools installed in `$GOPATH/bin`.)
* [`kubectl` command line](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-using-curl)
  and optionally `helm`. If you are running Linux 64-bit, you can skip
  this step as the script can download `kubectl` or `helm` automatically.

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
    $ hisk8s.sh _test_hem

This will install two helm charts

    $ _helm list
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

### Known issues

1. `kube proxy` may not work, as the cluster (aka virtualbox) network
   is not reachable from your laptop (where `kubectl` installed.)

### Tearing down

    $ hisk8s.sh _vagrant destroy -f

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
