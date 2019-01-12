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

### Bootstrap the cluster

```
./bin/hisk8s.sh _test
./bin/hisk8s.sh _smoke_tests
```

`kubectl` configuration will be stored under `./etc/.kube/config`.
You can execute the tool via the wrapper, for examples:

```
./bin/histk8s.sh _kubectl get nodes
```

### Debugging

To enter a node, use the wrapper script:

```
./bin/hisk8s.sh _ssh_list
./bin/hisk8s.sh _ssh 111
```

You can also use different aliases provided in the output of `_ssh_list`.

### Tear down

```
./bin/hisk8s.sh _vagrant_do destroy -f
```

[the-hard-way]: https://github.com/kelseyhightower/kubernetes-the-hard-way
