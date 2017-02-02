#!/bin/bash
list=$(docker ps -a |grep 'damp_proxysql')
if [[ "$list" != "" ]]
then
    echo "Stopping and removing the existing damp_proxysql container"
    docker stop  damp_proxysql
    docker rm -v damp_proxysql
fi
docker run   -p 6032:6032 -p 6033:6033 -v `pwd`:/root/build --name damp_proxysql -it damp

