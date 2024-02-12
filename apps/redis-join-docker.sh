#!/bin/bash

echo "start redis-join-docker.sh"

nodeName="redis-node-${1:-1}"
echo "nodeName: $nodeName"

docker exec -it "$nodeName" bash

echo "finish redis-join-docker.sh"