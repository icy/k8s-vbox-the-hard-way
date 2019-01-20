## Bootstrap a k8s cluster the hardway with VirtualBox

[k8s the hardway](https://github.com/kelseyhightower/kubernetes-the-hard-way)
requires an admin access on GKE.
I slightly modify the process to bootstrap a k8s cluster
on my VirtualBox environment (thanks to Vagrant.)
And yes I have a script to automate the process.

## Getting started

### Install basic tools

* VirtualBox (`pacman -S virtualbox`)
* Vagrant (`pacman -S vagrant`)
* https://github.com/cloudflare/cfssl (Please install all tools with
  `go get -u github.com/cloudflare/cfssl/cmd/...` and modify your `PATH`
  environment variable to recognize these new tools installed in `$GOPATH/bin`.)
* [`kubectl` command line](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-using-curl)

### Bootstrapping the cluster

Edit some basic settings in `./etc/custom.env.sh` and start the cluster:

    $ ./bin/hisk8s.sh        # Getting some helps
    $ ./bin/hisk8s.sh _env   # Print basic information
    $ ./bin/hisk8s.sh _test  # Create new cluster

### Testing

#### Running smoke tests

These tests are inspired by the original `k8s the hard way`; you have
to clean up the pods and services after the tests. You may want to skip
to the next section instead.

    $ ./bin/hisk8s.sh _smoke_tests
    $ ./bin/hisk8s.sh _smoke_test_deploy_app

`kubectl` configuration will be stored under `./etc/.kube/config`.
You can execute the tool via the wrapper, for examples:

    $ ./bin/hisk8s.sh _kubectl get nodes
    NAME         STATUS   ROLES    AGE    VERSION
    worker-141   Ready    <none>   100s   v1.12.0

(You can also use the shortcut `./bin/_kubectl`)

#### Testing with Helm

If you haven't installed `helm`, you can download them with `_wget_hem`
then move the binary from `caches/` to your search path.

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

    $ ./bin/hisk8s.sh _ssh_list
    $ ./bin/hisk8s.sh _ssh 111

You can also use different aliases provided in the output of `_ssh_list`.

### Tear down

    $ ./bin/hisk8s.sh _vagrant destroy -f

**Important notes**:
The script is stateless and it doesn't know if you have decreased the
number of workers/controllers. If you change `etc/customizations.env.sh`
the script probably can't help to destroy all nodes. If that's the case,
the best way is to restore the high number(s) and execute

    $ hisk8s.sh _vagrant destroy -f

because deleting nodes from `VirtualBox` doesn't help to remove some
port-forwarding settings.

## In-depth docs, details and customizations

### List of all steps to bootstrap new cluster

The list of all steps as in

  https://github.com/kelseyhightower/kubernetes-the-hard-way#labs

can be seen by using the `_steps` method:

    $ hisk8s.sh _steps

This prints the definition of the `_test` method.
