Ansible-MHA-Orchestrator-ProxySQL-Docker
============================================================
Teaching them to play together

**Now with Orchestrator!**

The big picture:
![img](http://i.imgur.com/sOKx0YL.png)


Presentation about [DAMP](http://www.slideshare.net/MiklosSzel/painless-mysql-ha-scalability-and-flexibility-with-ansible-mha-and-proxysql)



## Install
Prerequisities
 - Docker
 - GNU Bash

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
cluster of 3 machines (1 master -> 2 slaves) - GTID based replication
```
./damp_create_cluster.sh zaphod 3
```

cluster of 2 machines (1 master -> 1 slaves) - Regular replication
```
./damp_create_cluster.sh arthurdent 2 regular
```
The script generates the damp/hostfile Ansible inventory file.
```
[proxysql]
localhost


[damp_server_zaphod]
172.17.0.3 mysql_role=master
172.17.0.4 mysql_role=slave
172.17.0.5 mysql_role=slave

[damp_server_zaphod:vars]
cluster=damp_server_zaphod
hostgroup=1


[damp_server_arthurdent]
172.17.0.6 mysql_role=master
172.17.0.7 mysql_role=slave

[damp_server_arthurdent:vars]
cluster=damp_server_arthurdent
hostgroup=3
```

    
## start the Docker and install/setup ProxySQL(1.3.2)/MHA and sysbench  
```
./damp_start.sh
```

From inside the container run the following:
```
proxysql_menu.sh

ProxySQL admin
 1) ProxySQL Admin Shell
 2) [runtime] Show servers
 3) [runtime] Show users
 4) [runtime] Show replication_hostgroups
 5) [runtime] Show query_rules
 6) [runtime] Show global_variables
 7) [stats] Show connection_pool
 8) [stats] Show command_counters
 9) [stats] Show query digest
10) [stats] Show hostgroups
11) [log] Show connect
12) [log] Show ping
13) [log] Show read_only
14) [mysql][zaphod] Connect to cluster via ProxySQL
15) [test][zaphod] sysbench prepare
16) [test][zaphod] sysbench run - 15 sec, ro
17) [test][zaphod] sysbench run - 60 sec, ro
18) [test][zaphod] Split R/W
19) [test][zaphod] Create 'world' sample db
20) [HA][zaphod] MHA online failover (interactive)
21) [HA][zaphod] MHA online failover (noninteractive)
22) [mysql][arthurdent] Connect to cluster via ProxySQL
23) [test][arthurdent] sysbench prepare
24) [test][arthurdent] sysbench run - 15 sec, ro
25) [test][arthurdent] sysbench run - 60 sec, ro
26) [test][arthurdent] Split R/W
27) [test][arthurdent] Create 'world' sample db
28) [HA][arthurdent] MHA online failover (interactive)
29) [HA][arthurdent] MHA online failover (noninteractive)
30) Quit
```

This script can be also found outside of the container, but some options won't work from there (unless you have MHA/sysbench installed and set up:)).

These menupoint are self explanatory shortcuts to Linux commands/sqls. All commands/queries will be printed before execution.

Some expample outputs:

 2) [runtime] Show servers
```
+----+------------+------+--------+--------+-----------------+------------------------+
| hg | hostname   | port | status | weight | max_connections | comment                |
+----+------------+------+--------+--------+-----------------+------------------------+
| 1  | 172.17.0.3 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.4 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.5 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 3  | 172.17.0.6 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
| 4  | 172.17.0.7 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
+----+------------+------+--------+--------+-----------------+------------------------+
5 rows in set (0.01 sec)
```

3) [runtime] Show users
```
+----------+-------------------------------------------+----+--------+-----------------+
| username | password                                  | hg | active | max_connections |
+----------+-------------------------------------------+----+--------+-----------------+
| app1     | *98E485B64DC03E6D8B4831D58E813F86025D7268 | 1  | 1      | 200             |
| app3     | *944C03A73AF6A147B01A747C5D4EF0FF4A714D2D | 3  | 1      | 200             |
| app1     | *98E485B64DC03E6D8B4831D58E813F86025D7268 | 1  | 1      | 200             |
| app3     | *944C03A73AF6A147B01A747C5D4EF0FF4A714D2D | 3  | 1      | 200             |
+----------+-------------------------------------------+----+--------+-----------------+
```
connect to the MySQL cluster as an 'app' (mysql-client -> ProxySQL -> MySQL instanes)
The username and the password will be the following 
```
hostgroup=1
username=app1
password=app1

hostgroup=3
username=app3
password=app3
etc.

host: 127.0.0.1
user: app#
passwd: app#
port: 6033
```


 4) [runtime] Show replication_hostgroups
```
+------------------+------------------+------------------------+
| writer_hostgroup | reader_hostgroup | comment                |
+------------------+------------------+------------------------+
| 1                | 2                | damp_server_zaphod     |
| 3                | 4                | damp_server_arthurdent |
+------------------+------------------+------------------------+
```
App user (default hostgroup is the hostgroup in the inventory file for a given cluster, the traffic will go there unless told otherwise):


###Example test scenario #1:
let's generate some traffic on the first cluster:
execute these one after another
```
15) [test][zaphod] sysbench prepare
16) [test][zaphod] sysbench run - 15 sec, ro
```

Then check the connection pool. We'll see that all traffic went to the master (reads and writes). By default ProxySQL sends all traffic to the writer_hostgroups
```
7) [stats] Show connection_pool

+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
| hostgroup | srv_host   | srv_port | status | ConnUsed | ConnFree | ConnOK | ConnERR | Queries | Bytes_data_sent | Bytes_data_recv | Latency_ms |
+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
| 1         | 172.17.0.3 | 3306     | ONLINE | 0        | 4        | 4      | 0       | 110150  | 6177839         | 264696684       | 175        |
| 3         | 172.17.0.6 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 222        |
| 4         | 172.17.0.7 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 279        |
| 2         | 172.17.0.4 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 238        |
| 2         | 172.17.0.5 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 159        |
+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
```
Tell ProxySQL to send all queries matching '^select' to the hostgroup 2 (readers)
```
18) [test][zaphod] Split R/W

Command: mysql -h 127.0.0.1 -uadmin -padmin -P6032  -e 'REPLACE INTO mysql_query_rules(rule_id,active,match_pattern,destination_hostgroup,apply) VALUES(1000,1,'^select',2,0);LOAD MYSQL QUERY RULES TO RUNTIME;SAVE MYSQL QUERY RULES TO DISK;\G
```
re-run the sysbench and check the connection pool afterwards
```
16) [test][zaphod] sysbench run - 15 sec, ro
7) [stats] Show connection_pool
+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
| hostgroup | srv_host   | srv_port | status | ConnUsed | ConnFree | ConnOK | ConnERR | Queries | Bytes_data_sent | Bytes_data_recv | Latency_ms |
+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
| 1         | 172.17.0.3 | 3306     | ONLINE | 0        | 4        | 4      | 0       | 121530  | 6240429         | 264696684       | 185        |
| 3         | 172.17.0.6 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 249        |
| 4         | 172.17.0.7 | 3306     | ONLINE | 0        | 0        | 0      | 0       | 0       | 0               | 0               | 278        |
| 2         | 172.17.0.4 | 3306     | ONLINE | 0        | 3        | 3      | 0       | 40173   | 1740087         | 110225431       | 271        |
| 2         | 172.17.0.5 | 3306     | ONLINE | 0        | 3        | 3      | 0       | 39487   | 1708053         | 108560759       | 202        |
+-----------+------------+----------+--------+----------+----------+--------+---------+---------+-----------------+-----------------+------------+
```
We can see that a lot of traffic went to the hostgroup 2 (readers)

Check the query digest too:
```
11) [stats] Show query digest
+----+----------+------------+----------------------------------------------------------------------------------+
| hg | sum_time | count_star | substr(digest_text,1,80)                                                         |
+----+----------+------------+----------------------------------------------------------------------------------+
| 1  | 21055026 | 68840      | SELECT c FROM sbtest1 WHERE id=?                                                 |
| 2  | 12534808 | 56900      | SELECT c FROM sbtest1 WHERE id=?                                                 |
| 1  | 10226315 | 6884       | SELECT DISTINCT c FROM sbtest1 WHERE id BETWEEN ? AND ?+? ORDER BY c             |
| 1  | 5391754  | 6884       | SELECT c FROM sbtest1 WHERE id BETWEEN ? AND ?+? ORDER BY c                      |
| 1  | 4179020  | 12574      | COMMIT                                                                           |
| 1  | 3754569  | 6884       | SELECT SUM(K) FROM sbtest1 WHERE id BETWEEN ? AND ?+?                            |
| 1  | 3214914  | 6884       | SELECT c FROM sbtest1 WHERE id BETWEEN ? AND ?+?                                 |
| 1  | 2609316  | 12574      | BEGIN                                                                            |
| 2  | 2170878  | 5690       | SELECT DISTINCT c FROM sbtest1 WHERE id BETWEEN ? AND ?+? ORDER BY c             |
| 1  | 2111828  | 4          | INSERT INTO sbtest1(k, c, pad) VALUES(?, ?, ?),(?, ?, ?),(?, ?, ?),(?, ?, ?),(?, |
| 2  | 1641139  | 5690       | SELECT c FROM sbtest1 WHERE id BETWEEN ? AND ?+? ORDER BY c                      |
| 2  | 1618228  | 5690       | SELECT SUM(K) FROM sbtest1 WHERE id BETWEEN ? AND ?+?                            |
| 2  | 1336262  | 5690       | SELECT c FROM sbtest1 WHERE id BETWEEN ? AND ?+?                                 |
| 1  | 380320   | 1          | CREATE INDEX k_1 on sbtest1(k)                                                   |
| 1  | 267295   | 1          | CREATE TABLE sbtest1 ( id INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, k INTEGER UN |
+----+----------+------------+----------------------------------------------------------------------------------+
```



###Example test scenario #2:
testing online failover while reading from a cluster (all servers are up and running we only change the replication topology)
login to the container in 2 terminals:
```
./proxysql_login_docker.sh
```
and execute proxysql_menu.sh in both of them.
check the serverlist:
```
2) [runtime] Show servers
+----+------------+------+--------+--------+-----------------+------------------------+
| hg | hostname   | port | status | weight | max_connections | comment                |
+----+------------+------+--------+--------+-----------------+------------------------+
| 1  | 172.17.0.3 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.4 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.5 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 3  | 172.17.0.6 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
| 4  | 172.17.0.7 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
+----+------------+------+--------+--------+-----------------+------------------------+
```
The current masters are the 172.17.0.3 and 172.17.0.6 (even hostgroups)
```
4) [runtime] Show replication_hostgroups
+------------------+------------------+------------------------+
| writer_hostgroup | reader_hostgroup | comment                |
+------------------+------------------+------------------------+
| 1                | 2                | damp_server_zaphod     |
| 3                | 4                | damp_server_arthurdent |
+------------------+------------------+------------------------+
```

execute the following in one terminal:
(skip 15) if you already ran it)
```
15) [test][zaphod] sysbench prepare

17) [test][zaphod] sysbench run - 60 sec, ro
```

while the sysbench running, execute the online interactive failover in the other terminal:
```
20) [HA][zaphod] MHA online failover (interactive. you have to answer YES twice)
From:
172.17.0.3(172.17.0.3:3306) (current master)
 +--172.17.0.4(172.17.0.4:3306)
 +--172.17.0.5(172.17.0.5:3306)

To:
172.17.0.4(172.17.0.4:3306) (new master)
 +--172.17.0.5(172.17.0.5:3306)
 +--172.17.0.3(172.17.0.3:3306)
```

The only things we noticed during the failover were some reconnects:
```
[  13s] threads: 4, tps: 341.04, reads: 4746.60, writes: 0.00, response time: 17.56ms (95%), errors: 0.00, reconnects:  0.00
[  14s] threads: 4, tps: 337.03, reads: 4767.49, writes: 0.00, response time: 22.38ms (95%), errors: 0.00, reconnects:  3.00
[  15s] threads: 4, tps: 297.84, reads: 4236.67, writes: 0.00, response time: 26.13ms (95%), errors: 0.00, reconnects:  4.00
[  16s] threads: 4, tps: 294.14, reads: 4097.92, writes: 0.00, response time: 26.56ms (95%), errors: 0.00, reconnects:  0.00
[  17s] threads: 4, tps: 398.98, reads: 5590.68, writes: 0.00, response time: 16.87ms (95%), errors: 0.00, reconnects:  0.00
```
otherwise everything was seamless.

```
2) [runtime] Show servers
+----+------------+------+--------+--------+-----------------+------------------------+
| hg | hostname   | port | status | weight | max_connections | comment                |
+----+------------+------+--------+--------+-----------------+------------------------+
| 1  | 172.17.0.4 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.3 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.4 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 2  | 172.17.0.5 | 3306 | ONLINE | 1      | 1000            | damp_server_zaphod     |
| 3  | 172.17.0.6 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
| 4  | 172.17.0.7 | 3306 | ONLINE | 1      | 1000            | damp_server_arthurdent |
+----+------------+------+--------+--------+-----------------+------------------------+
```
hostgroup 1 -> 172.17.0.4 (master)
hostgroup 2 -> 172.17.0.3,172.17.0.5 (slave)
ProxySQL detected the changes and reassigned the servers to the proper replication_hostgroups




----

####Edit the global configuration file if you want to change defaults, credentials, roles
damp/group_vars/all
the mysql sections shouldn't be modified 
roles_enabled:
    proxysql: true
    mha: true
    sysbench: true
    orchestrator:  true
```
proxysql:
  admin:
    host: 127.0.0.1
    port: 6032
    user: admin
    passwd: admin
    interface: 0.0.0.0
  app:
    user: app
    passwd: gempa
    default_hostgroup: 1
    port: 6033
    priv: '*.*:CREATE,DELETE,DROP,EXECUTE,INSERT,SELECT,UPDATE,INDEX'
    host: '%'
    max_conn: 200 
  monitor:
    user: monitor
    passwd: monitor
    priv: '*.*:USAGE,REPLICATION CLIENT'
    host: '%'
  global_variables:
    mysql-default_query_timeout: 120000
    mysql-max_allowed_packet: 67108864
    mysql-monitor_read_only_timeout: 600
    mysql-monitor_ping_timeout: 600
    mysql-max_connections: 1024

mysql:
    login_user: root
    login_passwd: mysecretpass
    repl_user: repl
    repl_passwd: slavepass
```

####Connect  manually:
ProxySQL admin interface (with any MySQL compatible client)
```
host: 127.0.0.1
user: admin
passwd: admin
port: 6032
```
without having MySQL client installed:
```
docker exec -it damp_proxysql mysql -h 127.0.0.1 -u admin  -padmin -P 6032
```

Run the following to reset the env and restart the test from scratch
(this removes every MySQL containers(*damp_server*) and the inventory file)
```
./dump_reset.sh
```

## Orchestrator

Orchestrator made part of the setup.
Since both Orchestrator and MHA run with auto deadmaster failover disabled by default they can be tested independently.

The playbook adds all MySQL clusters to the Orchestrator automagically:

Once the playbook is done point your browser to 
http://localhost:3000

![img](http://i.imgur.com/qLcK6CA.png)
![img](http://i.imgur.com/wVZBZfE.png)

Change this to true to enable automatic dead master failover with Orchestrator:
groups_vars/all
```
orchestrator:
    auto_failover: false
``` 


notes:
- the /etc/proxysql.cnf is configured via a template, but be aware that the ProxySQL only read it during the first start (when it create the sqlite database) - you can read more here https://github.com/sysown/proxysql/blob/master/doc/configuration_system.md
- mha config files can be found under /etc/mha/mha_damp_server_${clustername}.cnf
- ProxySQL log /var/lib/proxysql/proxysql.log

Useful links, articles:

https://github.com/sysown/proxysql/blob/master/doc/configuration_howto.md

http://www.slideshare.net/DerekDowney/proxysql-tutorial-plam-2016

http://www.slideshare.net/atezuysal/proxysql-use-case-scenarios-plam-2016

Thanks
- René Cannaò 
- Ben Mildren
- Dave Turner
- Derek Downey 
- Frédéric 'lefred' Descamps 
- Shlomi Noach

