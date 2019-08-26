# Kak Containers

This was an experiment I was playing with for setting up a "container" using just namespaces (PID, net, mount). There's no overlayfs, and no cgroups. It started for *reasons*, but ended up being a fun way to learn about namespaces.

This is not a hard security boundary, you can just change your shell back to a normal one to "break out", and it requires privileged containers, so don't try use it as a security boundary.

If you want to understand the detail, you can read more about [ip netns](http://man7.org/linux/man-pages/man8/ip-netns.8.html), [unshare](http://man7.org/linux/man-pages/man1/unshare.1.html), [nsenter](http://man7.org/linux/man-pages/man1/nsenter.1.html) and [containers from scratch](https://ericchiang.github.io/post/containers-from-scratch/).

## Building

Build the container like normal from within the kak-containers/ dir with:

`docker build -t kak-containers .`

## Running

You need to run the container as --privileged, for e.g.:

`docker run -it --privileged kak-containers`

Once it's running, you can create new shells in the same namespace with:

`docker exec -it <container> /bin/nssh`

or exec outside the container with:

`docker exec -it <container> /bin/bash`

## Extending

This doesn't do much other than jail a user right now. The trick is to extend it with other namespaces.

You can create another network and mount namespace easily with:

`ip netns add <NS Name>`

You can execute commands in there with:

`ip netns exec <NS Name> <command>`

## Overview

There are three components, the Dockerfile, the setup script (entrypoint) and the shell (nssh).

The Dockerfile is super simple. It just copies the name space shell and the setup script which do most of the work.

The setup script does a couple of things:
 
* creates a user networking name space with resolvconf hoop jumping
* creates a user chroot mostly bind mounted to the hosts's tld from root
* adds the special shell to shells
* creates a veth pair in the user namespace which is NAT'ed to the root

The namespace shell is where most of the magic comes in, it:

* Sets up our namespaces with unshare
* chroot's to the user mount space
* mounts sysfs from within that namespace using some self referencing
* runs our shell in there
* Find's any existing instances, and runs a subset with nsenter if unshare is already running
