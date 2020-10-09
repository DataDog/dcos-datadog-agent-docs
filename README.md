# Datadog Agent on DC/OS EE Strict Mode (DRAFT)

## Introduction

This guide covers deployment of the Datadog Agent and Mesos integrations on DC/OS Enterprise Edition configured to run in the [Strict mode](https://docs.d2iq.com/mesosphere/dcos/2.1/security/ent/#strict) security setting.

The following custom image is currently required for the Datadog Agent to be able to run in this configuration (`datadog/agent-dev:dcos-auth-token-py3`)

## Pre-Requisites

In order to follow this guide you need to have DC/OS CLI installed and be able to authenticate to your cluster with an account that has superuser privileges.

_Note: This guide has been tested with DC/OS Enterprise 2.1 but should work for ealier versions as well._

## Service Account

A service account needs to be created for Datadog Agent containers in order to access application endpoints on agent and master nodes. The service account principal name and the private key will be provided to the configuration of the Datadog Agent containers in the later steps of this guide.

Prior to creating the service account, generate the public/private keypair as follows:

```shell
dcos security org service-accounts keypair private-key.pem public-key.pem
```

Create the `datadog_agent` service account with the public-key.pem from the previous step:

```bash
dcos security org service-accounts create -p public-key.pem -d "Datadog Agent service account" datadog_agent
```

The following permissions need to be granted to this newly created service account:

```bash
dcos security org users grant datadog_agent dcos:mesos:agent:endpoint:path:/metrics/snapshot read
dcos security org users grant datadog_agent dcos:mesos:master:endpoint:path:/metrics/snapshot read
dcos security org users grant datadog_agent dcos:mesos:agent:framework:role read
dcos security org users grant datadog_agent dcos:mesos:agent:executor:app_id read
dcos security org users grant datadog_agent dcos:mesos:agent:task:app_id read
```

## Node Configuration

Before you can continue with the installation on the nodes of your cluster, you need to copy contents of the `./opt-datadog-agent` directory to your cluster:

```shell
$ tree ./opt-datadog-agent
./opt-datadog-agent
├── conf.d
│   ├── mesos_master.d
│   │   ├── conf.yaml
│   │   └── private-key.pem
│   └── mesos_slave.d
│       ├── conf.yaml
│       └── private-key.pem
└── cont-init.d
    └── 90-mesos.sh
```

Please make sure to replace the `private-key.pem` file with the contents of the private key generated for the service account.

The following steps rely on this configuraiton being available at `/opt/datadog-agent/`:

```shell
[centos@ip-172-16-31-66 ~]$ tree /opt/datadog-agent
/opt/datadog-agent
├── conf.d
│   ├── mesos_master.d       # required on master nodes
│   │   ├── conf.yaml
│   │   └── private-key.pem
│   └── mesos_slave.d        # required on agent nodes
│       ├── conf.yaml
│       └── private-key.pem
└── cont-init.d              # required on agent nodes
    └── 90-mesos.sh
```

As annotated, not all of these files need to be present on master and agent nodes, for simplicity we are copying the entire directory in both cases.

## Deployment on Agent Nodes

To deploy the Datadog Agent on the agent nodes of your DC/OS cluster please use [the following service manifest: [deploy/dcos-node-datadog-agent.json](deploy/dcos-node-datadog-agent.json).

Please make sure to replace the `<YOUR_DD_API_KEY>` with your Datadog API key and configure the number of instances to match the number of agent nodes in your cluster.

To deploy this manifest:

```bash
dcos marathon app add ./deploy/dcos-node-datadog-agent.json
```

In order to confirm the instances of the `datadog-agent` service are running:

```bash
dcos task list
    NAME           HOST        USER      STATE                                      ID                                                 AGENT ID                   REGION       ZONE
...
datadog-agent  172.16.25.120  nobody  TASK_RUNNING  datadog-agent.instance-10710907-097c-11eb-ab42-ce9d95de588e._app.1  d7175926-3120-4ae2-aa97-aa5998cab5e2-S2  us-east-2  us-east-2b
...
```

You can now login to the node running the agent(s) and confirm the configuration:

```bash
$ sudo docker ps
CONTAINER ID        IMAGE                                   COMMAND             CREATED             STATUS                  PORTS                                                        NAMES
165a2dbb1542        datadog/agent-dev:dcos-auth-token-py3   "/init"             11 hours ago        Up 11 hours (healthy)   0.0.0.0:8125->8125/udp, 8126/tcp, 0.0.0.0:31101->31101/tcp   mesos-f5058135-a03a-481a-92e4-c45dfdcaba16

$ sudo docker exec -it mesos-f5058135-a03a-481a-92e4-c45dfdcaba16 agent status
Getting the status from the agent.

====================================
Agent (v7.24.0-devel+git.14.c805c57)
====================================
...
    mesos_slave (2.5.0)
    -------------------
      Instance ID: mesos_slave:946d0130dd0e818d [OK]
      Configuration Source: file:/etc/datadog-agent/conf.d/mesos_slave.d/conf.yaml
      Total Runs: 2,601
      Metric Samples: Last Run: 37, Total: 96,237
      Events: Last Run: 0, Total: 0
      Service Checks: Last Run: 2, Total: 5,202
      Average Execution Time : 60ms
      Last Execution Date : 2020-10-09 02:26:53.000000 UTC
      Last Successful Execution Date : 2020-10-09 02:26:53.000000 UTC
      metadata:
        version.major: 1
        version.minor: 10
        version.patch: 1
        version.raw: 1.10.1
        version.scheme: semver
...


```

## Deployment on Master Nodes

To deploy the Datadog Agent on the agent nodes of your DC/OS cluster please use [the following Docker command:

```bash
sudo docker run -d --name datadog-agent \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /proc/:/host/proc/:ro \
  -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
  -v /opt/datadog-agent/conf.d/mesos_master.d:/conf.d/mesos_master.d:ro \
  -e DD_API_KEY=$DD_API_KEY \
  -e MESOS_MASTER=true \
  -e MARATHON_URL=http://leader.mesos:8080 \
  datadog/agent-dev:dcos-auth-token-py3
```

Once the container is started you can confirm that the `mesos_master.d` check is operational:

```bash
$ sudo docker exec -it datadog-agent agent status
Getting the status from the agent.

====================================
Agent (v7.24.0-devel+git.14.c805c57)
====================================

    mesos_master (1.10.0)
    ---------------------
      Instance ID: mesos_master:1f7646a564f49e9e [OK]
      Configuration Source: file:/etc/datadog-agent/conf.d/mesos_master.d/conf.yaml
      Total Runs: 131
      Metric Samples: Last Run: 82, Total: 10,742
      Events: Last Run: 0, Total: 0
      Service Checks: Last Run: 1, Total: 131
      Average Execution Time : 49ms
      Last Execution Date : 2020-10-09 02:32:06.000000 UTC
      Last Successful Execution Date : 2020-10-09 02:32:06.000000 UTC
      metadata:
        version.major: 1
        version.minor: 10
        version.patch: 1
        version.raw: 1.10.1
        version.scheme: semver
```
