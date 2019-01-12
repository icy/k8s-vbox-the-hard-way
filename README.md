## Bootstrap a k8s cluster the hardway with VirtualBox

[k8s the hardway is fun](the-hard-way) requires an admin access on GKE.
I slightly modify the process to bootstrap a k8s cluster
on my VirtualBox environment (thanks to Vagrant.)
And yes I have a script to automate the process.

## Requirements

* VirtualBox
* Vagrant
* https://github.com/cloudflare/cfssl (Please install all tools with
  `go get -u github.com/cloudflare/cfssl/cmd/...` and modify your `PATH`
  environmant to recognize these new tools installed in `$GOPATH/bin`.)
* `kubectl` command line

[the-hard-way]: https://github.com/kelseyhightower/kubernetes-the-hard-way
