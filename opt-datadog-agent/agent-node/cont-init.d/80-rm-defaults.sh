#!/bin/bash

# Remove all default checks (Datadog Agent Cluster Worker)
# Note: this has to be executed prior to `89-copy-customfiles.sh`:
# https://github.com/DataDog/datadog-agent/blob/master/Dockerfiles/agent/entrypoint/89-copy-customfiles.sh
rm -rf /etc/datadog-agent/conf.d
