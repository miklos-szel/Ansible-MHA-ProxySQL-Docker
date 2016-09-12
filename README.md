Docker-Anisble-MHA-ProxySQL[DAMP]
============================================================
Teaching them to play together

## Install
Prerequisities
 - Docker
 - Bash

Docker: 
```
brew cask install docker
```
(you have to open docker from the applications and follow the steps, if you can execute 'docker ps' from a terminal, you are all set)


## Build the docker image
```
docker build -t damp .
````

## Create some MySQL test clusters
cluster of 3 machines (1 master -> 2 slaves)
```
./mysql_start.sh zaphod 3
```

cluster of 2 machines (1 master -> 1 slaves)
```
./mysql_start.sh arthurdent 2
```
The script generates the damp/roles/proxysql/vars/servers.yml file that will be parsed by ansible during the next step.
```
mysql_servers:
  - clustername: damp_server_zaphod
    hostgroup: 1
    master:
        - 172.17.0.2
    servers:
      - 172.17.0.2
      - 172.17.0.3
      - 172.17.0.4
  - clustername: damp_server_arthurdent
    hostgroup: 3
    master:
        - 172.17.0.5
    servers:
      - 172.17.0.5
      - 172.17.0.6
```

## start the Docker and install/setup ProxySQL (1.2.2)  
```
./ansible_start.sh
```

connect to the ProxySQL admin interface:
```
docker exec -it damp_proxysql mysql -h 127.0.0.1 -u admin  -padmin -P 6032
or
./proxysql_admin.sh
```

connect to the MySQL cluster as an 'app' (mysql-client -> ProxySQL -> MySQL instanes)
```
docker exec -it damp_proxysql mysql -h 127.0.0.1 -u app  -pgempa -P 6033
or
./proxysql_app.sh
```

Some notes:
- the /etc/proxysql.cnf file left intact intentionally to avoid confusion, the ProxySQL only read it during the first start (when it create the sqlite database) - you can read more here https://github.com/sysown/proxysql/blob/master/doc/configuration_system.md
- Every request the 'app' user executes goes to the hostgroup=1 which is the first cluster (fow now)
- in case of an error message:
```
~/Projects/Docker/Docker-Anisble-ProxySQL-MHA$ ./ansible_start.sh
docker: Error response from daemon: Conflict. The name "/damp_proxysql" is already in use by container d481f132fe47012759de349402eb4a162e7d95649a9b1b030769ef5a868bb461. You have to remove (or rename) that container to be able to reuse that name..
```
run
```
docker stop damp_proxysql
docker rm damp_proxysql
```

List of MySQL servers:
```
mysql> select * from runtime_mysql_servers;
+--------------+------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| hostgroup_id | hostname   | port | status | weight | compression | max_connections | max_replication_lag | use_ssl | max_latency_ms | comment |
+--------------+------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
| 1            | 172.17.0.2 | 3306 | ONLINE | 1      | 0           | 1000            | 20                  | 0       | 0              |         |
| 3            | 172.17.0.5 | 3306 | ONLINE | 1      | 0           | 1000            | 20                  | 0       | 0              |         |
| 2            | 172.17.0.3 | 3306 | ONLINE | 1      | 0           | 1000            | 20                  | 0       | 0              |         |
| 2            | 172.17.0.4 | 3306 | ONLINE | 1      | 0           | 1000            | 20                  | 0       | 0              |         |
| 4            | 172.17.0.6 | 3306 | ONLINE | 1      | 0           | 1000            | 20                  | 0       | 0              |         |
+--------------+------------+------+--------+--------+-------------+-----------------+---------------------+---------+----------------+---------+
5 rows in set (0.01 sec)
```
List of hostgroups:
```
mysql> select * from runtime_mysql_replication_hostgroups;
+------------------+------------------+------------------------+
| writer_hostgroup | reader_hostgroup | comment                |
+------------------+------------------+------------------------+
| 1                | 2                | damp_server_zaphod     |
| 3                | 4                | damp_server_arthurdent |
+------------------+------------------+------------------------+
2 rows in set (0.00 sec)
```
App user (default hostgroup is 1, the traffic will go there unless told otherwise):
```
mysql> select * from mysql_users;
+----------+----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
| username | password | active | use_ssl | default_hostgroup | default_schema | schema_locked | transaction_persistent | fast_forward | backend | frontend | max_connections |
+----------+----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
| app      | gempa    | 1      | 0       | 1                 | NULL           | 0             | 0                      | 0            | 1       | 1        | 200             |
+----------+----------+--------+---------+-------------------+----------------+---------------+------------------------+--------------+---------+----------+-----------------+
1 row in set (0.00 sec)
```

###TODO:
- add MHA(in progress)
- add databases and some test scenarios

Thanks
- René Cannaò 
- Derek Downey 

