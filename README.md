# Datadog Agent on DC/OS Enterprise with Strict Mode

## Introduction

This guide covers deployment of the Datadog Agent and Mesos integrations on DC/OS Enterprise Edition configured to run
in the [Strict mode](https://docs.d2iq.com/mesosphere/dcos/2.1/security/ent/#strict) security setting.

## Pre-Requisites

In order to follow this guide you need to have DC/OS CLI installed and be able to authenticate to your cluster with an
account that has superuser privileges.

Configuration described here is supported with the Datadog Agent version 7.24.0 and higher.

_Note: This guide has been tested with DC/OS Enterprise 1.14-2.1 but should work for ealier versions as well._

## Datadog Agent Service Account

A service account needs to be created for the Datadog Agent containers in order to be able access application endpoints
on agent and master nodes. The service account principal name and the private key will be provided to the configuration
of the Datadog Agent containers in the later steps of this guide.

Prior to creating the service account, generate the public/private keypair as follows:

```shell
dcos security org service-accounts keypair private-key.pem public-key.pem
```

Create the `datadog_agent` service account with the public-key.pem from the previous step:

```shell
dcos security org service-accounts create -p public-key.pem -d "Datadog Agent service account" datadog_agent
```

The following permissions need to be granted to this newly created service account:

```shell
dcos security org users grant datadog_agent dcos:mesos:agent:endpoint:path:/metrics/snapshot read
dcos security org users grant datadog_agent dcos:mesos:master:endpoint:path:/metrics/snapshot read
dcos security org users grant datadog_agent dcos:mesos:agent:framework:role read
dcos security org users grant datadog_agent dcos:mesos:agent:executor:app_id read
dcos security org users grant datadog_agent dcos:mesos:agent:task:app_id read
```

## Node Configuration

Before you can continue with the installation on the nodes of your cluster, you need to copy contents of the
`./opt-datadog-agent` directory to your cluster:

```shell
$ tree ./opt-datadog-agent
./opt-datadog-agent
├── agent-node
│   ├── agent
│   │   └── conf.d
│   │       └── mesos_slave.d
│   │           └── conf.yaml
│   ├── cluster-worker
│   │   └── conf.d
│   │       ├── marathon.d
│   │       │   └── conf.yaml
│   │       └── spark.d
│   │           └── conf.yaml
│   └── cont-init.d
│       ├── 80-rm-defaults.sh
│       └── 90-mesos.sh
├── master-node
│   └── conf.d
│       └── mesos_master.d
│           └── conf.yaml
└── service-account
    └── private-key.pem
```

Please make sure to copy the private key `private-key.pem` generated for the service account to the `service-account` directory.

The following steps rely on this configuraiton being available at `/opt/datadog-agent/` on each of the cluster nodes:

```shell
[centos@ip-172-16-0-56 ~]$ tree /opt/datadog-agent/
/opt/datadog-agent/
├── agent-node                # required on agent nodes
│   ├── agent
│   │   └── conf.d
│   │       └── mesos_slave.d
│   │           └── conf.yaml
│   ├── cluster-worker
│   │   └── conf.d
│   │       ├── marathon.d
│   │       │   └── conf.yaml
│   │       └── spark.d
│   │           └── conf.yaml
│   └── cont-init.d
│       ├── 80-rm-defaults.sh
│       └── 90-mesos.sh
├── master-node               # required on master nodes
│   └── conf.d
│       └── mesos_master.d
│           └── conf.yaml
└── service-account           # required on all nodes
    └── private-key.pem
```

As annotated, not all of these files need to be present on master and agent nodes, for simplicity we are copying the
entire directory in both cases.

## Datadog Agent Deployment on Mesos Agent Nodes

To deploy the Datadog Agent on the agent nodes of your DC/OS cluster please use the following service manifest:
[deploy/dcos-node-datadog-agent.json](deploy/dcos-node-datadog-agent.json).

Please make sure to replace the `<YOUR_DD_API_KEY>` with your Datadog API key and configure the number of instances to
match the number of agent nodes in your cluster.

To deploy this manifest:

```shell
dcos marathon app add ./deploy/dcos-node-datadog-agent.json
```

In order to confirm the instances of the `datadog-agent` service are running:

```shell
dcos task list
    NAME           HOST        USER      STATE                                      ID                                                 AGENT ID                   REGION       ZONE
...
datadog-agent  172.16.25.120  nobody  TASK_RUNNING  datadog-agent.instance-10710907-097c-11eb-ab42-ce9d95de588e._app.1  d7175926-3120-4ae2-aa97-aa5998cab5e2-S2  us-east-2  us-east-2b
...
```

You can now login to the node running the agent(s) and confirm the configuration:

```shell
$ sudo docker ps
CONTAINER ID        IMAGE                                   COMMAND             CREATED             STATUS                  PORTS                                                        NAMES
165a2dbb1542        datadog/agent:7.24.1-jmx      "/init"             11 hours ago        Up 11 hours (healthy)   0.0.0.0:8125->8125/udp, 8126/tcp, 0.0.0.0:31101->31101/tcp   mesos-f5058135-a03a-481a-92e4-c45dfdcaba16

$ sudo docker exec -it mesos-f5058135-a03a-481a-92e4-c45dfdcaba16 agent status
Getting the status from the agent.

====================================
Agent (v7.24.1)
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

## Datadog Cluster Worker Deployment on Mesos Agent Nodes

Cluster Worker is a deployment of Datadog Agent intended to run cluster level checks.

To deploy the Datadog Agent on the agent nodes of your DC/OS cluster please use the following service manifest:
[deploy/dcos-node-datadog-cluster-worker.json](deploy/dcos-node-datadog-cluster-worker.json).

Please make sure to replace the `<YOUR_DD_API_KEY>` with your Datadog API key.

To deploy this manifest:

```shell
dcos marathon app add ./deploy/dcos-node-datadog-agent.json
```

Currently the following integrations are enabled in the Cluster Worker:

* [Marathon](./opt-datadog-agent/agent-node/cluster-worker/conf.d/marathon.d/conf.yaml)

* [Spark](./opt-datadog-agent/agent-node/cluster-worker/conf.d/spark.d/conf.yaml)

### Spark Integration

Note that the Spark integration requires Spark History server to be configured in the cluster.
Please refer to the section in the Appendix to confirm your Spark installation is correct.

Note that the cluster name reported by the Spark integration is configured in the `conf.yaml` file:

```yaml
    cluster_name: your-cluster-name
```

To confirm the Spark integration is configured and is running correctly:

```shell
$ sudo docker exec -it <container-id> agent status
...
    spark (1.15.0)
    --------------
      Instance ID: spark:f52067a81febe1ce [OK]
      Configuration Source: file:/etc/datadog-agent/conf.d/spark.d/conf.yaml
      Total Runs: 11,250
      Metric Samples: Last Run: 172, Total: 836,910
      Events: Last Run: 0, Total: 0
      Service Checks: Last Run: 4, Total: 33,795
      Average Execution Time : 139ms
      Last Execution Date : 2020-10-15 18:16:47.000000 UTC
      Last Successful Execution Date : 2020-10-15 18:16:47.000000 UTC
      metadata:
        version.major: 2
        version.minor: 4
        version.patch: 6
        version.raw: 2.4.6
        version.scheme: semver
```

Note that the `<container-id>` corresponds to the docker container id launched on the node where the Cluster Worker is
currently running. To identify the node:

```shell
$ dcos task list
...
  datadog-agent-cluster-worker  172.16.7.68    nobody  TASK_RUNNING  datadog-agent-cluster-worker.instance-5bab8984-1d36-11eb-8e5d-a2cf47f4afdc._app.1  f3e75cfc-843e-49e7-85db-494ebcc225dc-S0  us-east-2  
```

Running `agent check spark` within the container should provide additional information regarding reported metrics:

```shell
$ sudo docker exec -it <container-id> agent check spark
...
=== Series ===
    {
      "metric": "spark.job.num_completed_stages",
      "points": [
        [
          1602786456,
          2
        ]
      ],
      "tags": [
        "app_name:Spark Pi",
        "cluster_name:your-cluster-name",
        "job_id:0",
        "stage_id:0",
        "status:succeeded"
      ],
      "host": "i-0438d2f0fbdc7281d",
      "type": "count",
      "interval": 0,
      "source_type_name": "System"
    },
    ...

=== Service Checks ===
[
  {
    "check": "spark.driver.can_connect",
    "host_name": "i-0438d2f0fbdc7281d",
    "timestamp": 1602786456,
    "status": 0,
    "message": "Connection to Spark driver \"https://leader.mesos/service/spark-history\" was successful",
    "tags": [
      "cluster_name:your-cluster-name",
      "url:https://leader.mesos/service/spark-history"
    ]
  },
...
  {
    "check": "spark.application_master.can_connect",
    "host_name": "i-0438d2f0fbdc7281d",
    "timestamp": 1602786456,
    "status": 0,
    "message": "Connection to ApplicationMaster \"https://leader.mesos\" was successful",
    "tags": [
      "cluster_name:your-cluster-name",
      "url:https://leader.mesos"
    ]
  }
]
```

## Datadog Agent Deployment on Master Nodes

To deploy the Datadog Agent on the agent nodes of your DC/OS cluster please use [the following Docker command:

```shell
sudo docker run -d --name datadog-agent \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /proc/:/host/proc/:ro \
  -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
  -v /opt/datadog-agent/master-node/conf.d:/conf.d:ro \
  -e DD_API_KEY=$DD_API_KEY \
  -e MESOS_MASTER=true \
  -e MARATHON_URL=http://leader.mesos:8080 \
  datadog/agent-dev:dcos-auth-py3
```

Once the container is started you can confirm that the `mesos_master.d` check is operational:

```shell
$ sudo docker exec -it datadog-agent agent status
Getting the status from the agent.

====================================
Agent (v7.24.1)
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

## Appendix: Spark Configuration

> :warning: The following instructions are provided as a reference only. Please contact your Spark administrator to make
> sure these settings are applicable to your environment.

In order for the Datadog Agent Spark integration to be able to collect metrics in the DC/OS running in Strict security
mode the Spark and Spark History Server packages have to be configured according to the D2IQ security recommendations
for this mode of operation. Note also that Spark History Server requires HDFS to be installed as a dependency.

1. Install HDFS

Note that HDFS installation requries 5 private agent nodes. Please confirm that HDFS is running with a service account
and configured in accordance with best practices outlined in the [Operations/Security
section](https://docs.d2iq.com/mesosphere/dcos/services/hdfs/2.8.0-3.2.1/operations/security/).

2. Add permission for `root` user under `dcos_marathon` to allow it to run services as `root`

Permissions are:

```shell
dcos:mesos:master:task:user:root   create
dcos:mesos:agent:task:user:root    create
```

These will be necessary for the HDFS client deployment in the next step.

3. Install HDFS Client

Please review the provided options file and adjust according to your enviroment.

```shell
dcos marathon app add ./deploy/hdfsclient.json
```

4. Create a service account and secret for Spark History Server and Spark.

To create the service account you can use the following dcos cli commands:

```shell
# Create the keypair
dcos security org service-accounts keypair spark-private-key.pem spark-public-key.pem
# Create the service account
dcos security org service-accounts create -p spark-public-key.pem -d "Spark service account" spark
# Create the service account secret

```

Make sure that you have added all the basic permission under the service account you
just created, required to run the Spark Job.

If the service account name is `spark` than Following would be the bare minimum list:

```shell
dcos:mesos:agent:task:user:nobody                       create
dcos:mesos:agent:task:user:root                         create
dcos:mesos:master:framework:role:spark-dispatcher       create
dcos:mesos:master:reservation:principal:spark           delete
dcos:mesos:master:reservation:role:spark-dispatcher     create
dcos:mesos:master:task:app_id:/spark                    create
dcos:mesos:master:task:user:nobody                      create
dcos:mesos:master:task:user:root                        create
dcos:mesos:master:volume:principal:spark                delete
dcos:mesos:master:volume:role:spark-dispatcher          create
```

These permissions can be granted to the `spark` service account with:

```shell
dcos security org users grant spark ..
```

5. Install Spark History Server

_Note: Please review the provided options file and adjust according to your environment requirements._

```shell
dcos package install spark-history --options=./deploy/spark-history-options.json
```

6. Install Spark

_Note: Please review the provided options file and adjust according to your environment requirements._

```shell
dcos package install spark --options=./deploy/spark-options.json
```

7. Validate Spark installation

To validate the installation you can submit a test job as follows:

```shell
dcos spark run --submit-args="--conf spark.eventLog.enabled=true --conf spark.eventLog.dir=hdfs://hdfs/history --conf spark.mesos.principal=spark --conf spark.mesos.containerizer=mesos --class org.apache.spark.examples.SparkPi https://downloads.mesosphere.com/spark/assets/spark-examples_2.11-2.4.0.jar 100"
Using image 'mesosphere/spark:2.11.0-2.4.6-scala-2.11-hadoop-2.9' for the driver and the executors (from dispatcher: container.docker.image).
To disable this image on executors, set spark.mesos.executor.docker.forcePullImage=false
Run job succeeded. Submission id: driver-20201015180532-0008
```

Note the use of `spark.eventLog.enabled` `spark.eventLog.dir` settings along with the use of service account in the
`spark.mesos.principal`.

Once the job is started it should appear in Spark and Spark History Server:

```shell
$(dcos config show core.dcos_url)/service/spark # Spark web UI
```

```shell
$(dcos config show core.dcos_url)/service/spark-history # Spark History Server web UI
```
