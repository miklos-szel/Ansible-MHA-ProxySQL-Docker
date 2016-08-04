#!/bin/bash
#brew install gnu-sed
currdir=`pwd`
servers="$currdir/damp/roles/proxysql/vars/servers.yml"
#server1 will be the initial master

num_of_servers=2
server_name=damp_server

list=$(docker ps -a |grep ${server_name})
if [[ "$list" != "" ]]
then
    echo "containers with name: $server_name are already running, quit!"
    exit 1
fi

docker-ip() {
    local ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$@")
    echo $ip
}

#create n slaves based on the slave directory template
echo "mysql_servers:" > $servers

for i in $(seq 1  $num_of_servers)
do
echo $i
    mkdir -p $currdir/mysql_hosts/${server_name}${i}/conf.d $currdir/mysql_hosts/${server_name}${i}/log_mysql
    #cp -r $currdir/mysql_hosts/server_tmpl/ $currdir/mysql_hosts/${server_name}${i}
echo " $currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf"
echo $currdir/my.cnf
echo "s/server-id=/server-id=${i}/"
    if [ $i ==  "1" ] 
    then
        sed   -e "s/server-id=/server-id=1/" -e "s/read_only=1/read_only=0/"  $currdir/my.cnf> $currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
    else
        sed   -e  "s/server-id=/server-id=${i}/"  $currdir/my.cnf> $currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
    fi

    cid=$(docker run --name ${server_name}${i} -d -v $currdir/mysql_hosts/${server_name}${i}/conf.d:/etc/mysql/conf.d -v $currdir/mysql_hosts/${server_name}${i}/log_mysql:/var/log/mysql  -e MYSQL_ROOT_PASSWORD=mysecretpass -d percona:5.6)

    server_ip=$( docker-ip $cid )
    echo "${server_name}${i} $cid($server_ip)"
    echo "   ${server_name}${i}: $server_ip" >> $servers
    if [ $i ==  "1" ]
    then
        master_ip=$server_ip
    fi

done
#waiting the last server to be available
isup=0

until [ $isup -eq "1" ]

do
    isup=$(docker exec -ti ${server_name}${num_of_servers}  'mysql' -NB -uroot -pmysecretpass -e"select(234);" |grep "234" |wc -l )
    sleep 3
    echo "waiting the ${server_name}${num_of_servers} to be available"
done

echo "add replication user to the master (${server_name}1"
docker exec -ti ${server_name}1  'mysql' -uroot -pmysecretpass -vvv -e "GRANT REPLICATION SLAVE ON *.* TO repl@'%' IDENTIFIED BY 'slavepass'\G"

#configure replication on all hosts
for i in $(seq 2  $num_of_servers)
do

    docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"change master to master_host='$master_ip',master_user='repl',master_password='slavepass',master_log_file='mysqld-bin.000004',master_log_pos=310;" -vvv

    echo "start replication"
    docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"START SLAVE\G" -vvv 

    echo "show slave status"
    docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"SHOW SLAVE STATUS\G" -vvv

done
