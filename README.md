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
./mysql_create_cluster.sh zaphod 3
```

cluster of 2 machines (1 master -> 1 slaves)
```
./mysql_create_cluster.sh arthurdent 2
```
The script generates the damp/hostfile Ansible inventory file.
```
[proxysql]
localhost


[damp_server_zaphod]
172.17.0.2 mysql_role=master
172.17.0.3 mysql_role=slave
172.17.0.4 mysql_role=slave

[damp_server_zaphod:vars]
cluster=damp_server_zaphod
hostgroup=1


[damp_server_arthurdent]
172.17.0.5 mysql_role=master
172.17.0.6 mysql_role=slave

[damp_server_arthurdent:vars]
cluster=damp_server_arthurdent
hostgroup=3
```

## start the Docker and install/setup ProxySQL (1.3.0g)  
```
./ansible_start.sh
```

connect to the ProxySQL admin interface:
```
./proxysql_admin.sh
```
You can also use any MySQL compatible client:
```
host: 127.0.0.1
user: admin
passwd: admin
port: 6032

```

connect to the MySQL cluster as an 'app' (mysql-client -> ProxySQL -> MySQL instanes)
```
./proxysql_app.sh
```
You can also use any MySQL compatible client:
```
host: 127.0.0.1
user: app
passwd: gempa
port: 6033
```

Run the following to reset the env and restart the test from scratch
(this removes every MySQL containers(*damp_server*) and the inventory file)
```
./dump_reset.sh
```


Some notes:
- the /etc/proxysql.cnf file left intact intentionally to avoid confusion, the ProxySQL only read it during the first start (when it create the sqlite database) - you can read more here https://github.com/sysown/proxysql/blob/master/doc/configuration_system.md
- Every request the 'app' user executes goes to the hostgroup=1 which is the first cluster (for now)

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
- Ben Mildren
