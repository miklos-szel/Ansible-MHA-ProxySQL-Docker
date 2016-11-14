docker stop damp_proxysql
docker rm damp_proxysql
docker run   -p 6032:6032 -p 6033:6033 -v `pwd`:/root/build --name damp_proxysql -it damp

