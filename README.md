[![Build Status](https://github.com/atgreen/simple-scaler/actions/workflows/build.yml/badge.svg)](https://github.com/atgreen/simple-scaler/actions)

# simple-scaler

simple-scaler scales a series of pre-configured Azure-hosted
OpenShift worker nodes up and down by simply turning them on and off
in an ordered sequence.  Once 'off', the VM is 'deallocated', meaning
that the only ongoing charge will be for the VM disk image (as low as
$3/month).  Once 'on', the pre-configured worker node will reattach
to the cluster and start taking on load.

![alt text](simple-scaler.png "Stretching your cluster to Azure")


The worker nodes must have a standard name template with a numeric
suffix representing its position in the sequence, starting
from 1. So, for instance, with a name template of `azworker-`, the VMs
must be named `azworker-1`, `azworker-2`, `azworker-3`, etc.  Note
that your network must allow for every node must be route to every
other node.

simple-scaler is monitored and controlled over a simple web API.

```
$ curl http://localhost:8080
{ "target": 2, "ready": 2, "vms": 2, "active-change-timer": 0, "last-change-timer": 1234 }
```

 * `target` is the number of `simple-scaler`-managed OpenShift nodes we are aiming to have ready.
 * `ready` is the number of `simple-scaler`-managed ready nodes in the OpenShift cluster.
 * `vms` is the number of VMs that are on, regardless of whether of not they are ready
 * `active-change-timer` is the number of seconds `simple-scaler` has been working on a change, or `0`
 * `last-change-timer` is the number of seconds since our last completed change, or `0` if there's an ongoing change

```
$ curl http://localhost:88080/set-target?target=5
{ "target": 5, "ready": 2, "vms": 2, "active-change-timer": 1, "last-change-timer": 0 }
```

This sets the `target` to 5, and will initiate VM on/off switching if
we don't already have 5 ready systems.

Common sense restrictions apply around the use of storage.  Consider
using taints and tolerations to restrict the kinds of workloads that
will run on the Azure-hosted nodes.


Configuration
-------------

simple-scaler expects to find a kubeconfig file at `/etc/simple-scaler/kubeconfig`.

simple-scaler is customized through a [TOML](https://toml.io)
formatted configuration file, `/etc/simple-scaler/config.ini`.

In the `[azure]` section:

| Setting          | Description                                         |
|------------------|----------------------------------------------------- |
| `max-nodes`      | The maximum number of pre-configured nodes          |
| `tenant`         | The azure tenant ID                                 |
| `resource-group` | The dedicated azure resource group for worker nodes |
| `name-template`  | The prefix for all VM names (eg. "azworker-")       |
| `sp-appid`       | The service principal app ID for managing VMs       |
| `sp-password`    | The service principal password for managing VMs     |

simple-scaler runs on top of an embedded [etcd](https://etcd.io/)
database that runs as an asynchronous child process to simple-scaler
(see [cl-etcd](https://github.com/atgreen/cl-etcd)).  Resilience is
maintained by load-balancing multiple instances of simple-scaler, and
clustering the underlying `etcd` service.  This cluster of one, three
or five nodes, is configured in the `[etcd]` section of
`/etc/simple-scaler/config.ini`.

| Setting                       | Description                                    |
|-------------------------------|------------------------------------------------  |
| `name`                        | The name of this etcd node                     |
| `debug-trace`                 | Any value enables logging of all etcd messages |
| `data-dir`                    | Path to persistent storage                     |
| `initial-advertise-peer-urls` | See etcd documentation                         |
| `listen-peer-urls`            | See etcd documentation                         |
| `listen-client-urls`          | See etcd documentation                         |
| `advertise-client-urls`       | See etcd documentation                         |
| `initial-cluster`             | See etcd documentation                         |

`simple-scaler` is designed to run in kubernetes-managed containers.
Be sure to create persistent volumes for `data-dir`, otherwise etcd
nodes will not be able to rejoin the cluster if they are ever
restarted.  A good location for this might be
`/var/lib/simple-scaler`.  See the example k8s yaml files in the `k8s`
directory for details.

Author & License
=================

simple-scaler is an experiment by [Anthony
Green](https://linkedin.com/in/green), and is licensed under the terms
of the GNU Affero General Public License.  See the file COPYING for
details.
