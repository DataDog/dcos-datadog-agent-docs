#!/bin/bash

# Enable the Mesos integrations if relevant

CONFD=/etc/datadog-agent/conf.d

if [[ $MESOS_SLAVE ]]; then
  sed -i -e "s/localhost/$HOST/" $CONFD/mesos_slave.d/conf.yaml
fi
