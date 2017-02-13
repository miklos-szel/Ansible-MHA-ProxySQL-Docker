#!/bin/bash
user=admin
passwd=admin
host=127.0.0.1
port=6032
app_port=6033
pcmd="mysql -h $host -u$user -p$passwd -P$port "
while true
do
    echo "ProxySQL admin"
    options=(
        "ProxySQL Admin Shell"
        "MySQL Connect to 'zaphod' via ProxySQL"
        "MySQL Connect to 'arthurdent' via ProxySQL"
        "[runtime] Show servers"
        "[runtime] Show users"
        "[runtime] Show repliation_hostgroups"
        "[runtime] Show query_rules"
        "[stats] Show connection_pool"
        "[stats] Show command_counters"
        "[stats] Show query digest"
        "[stats] Show hostgroups"
        "[log] Show connect"
        "[log] Show ping"
        "[log] Show read_only"
        "[test][zaphod] sysbench prepare"
        "[test][zaphod] sysbench run - 15 sec, ro"
        "[test][zaphod] sysbench run - 60 sec, ro"
        "[test][zaphod] Split R/W"
        "[test][zaphod] Create 'world' sample db"
        "[HA][zaphod] MHA online failover (interactive)"
        "[HA][zaphod] MHA online failover (noninteractive)"
        "[test][arthurdent] sysbench prepare"
        "[test][arthurdent] sysbench run - 15 sec, ro"
        "[test][arthurdent] sysbench run - 60 sec, ro"
        "[test][arthurdent] Split R/W"
        "[test][arthurdent] Create 'world' sample db"
        "[HA][arthurdent] MHA online failover (interactive)"
        "[HA][arthurdent] MHA online failover (noninteractive)"
        "Quit")
    PS3='Please enter your choice: '
    
    exec_query () {
        query=$1
        echo "####"
    echo "Command: $pcmd -e '$query' "
    echo "####"
    $pcmd "-e $query"
    }

    exec_cmd () {
        cmd=$1
        echo "####"
    echo "Command: $cmd "
    echo "####"
    $cmd
    }

    select opt in "${options[@]}"
    do
    case $opt in
        "ProxySQL Admin Shell")
            $pcmd
            break
            ;;

        "MySQL Connect to 'zaphod' via ProxySQL")
            cmd="mysql -h $host --user=app1 --password=app1 --port $app_port"
            exec_cmd "$cmd"
            break
            ;;

        "MySQL Connect to 'arthurdent' via ProxySQL")
            cmd="mysql -h $host --user=app3 --password=app3 --port $app_port"
            exec_cmd "$cmd"
            break
            ;;

        "[runtime] Show servers")
            query="SELECT hostgroup_id as hg, hostname,port,status,weight,max_connections, comment FROM runtime_mysql_servers ORDER BY hostgroup_id,hostname ASC;"
            exec_query "$query"
            break
            ;;
        "[runtime] Show users")
            query="SELECT username,password,default_hostgroup as hg, active,max_connections FROM runtime_mysql_users;"
            exec_query "$query"
            break
            ;;

        "[runtime] Show repliation_hostgroups")
            query="SELECT * FROM runtime_mysql_replication_hostgroups"
            exec_query "$query"
            break
            ;;

        "[runtime] Show query_rules")
            query="SELECT rule_id, match_digest, match_pattern, replace_pattern, cache_ttl, destination_hostgroup hg,apply FROM mysql_query_rules ORDER BY rule_id;"
            exec_query "$query"
            break
            ;;

        "[stats] Show connection_pool")
            query="SELECT * FROM stats.stats_mysql_connection_pool;"
            exec_query "$query"
            break
            ;;
        "[stats] Show command_counters")
            query="SELECT Command,Total_Time_us, Total_cnt FROM stats_mysql_commands_counters WHERE Total_cnt;"
            exec_query "$query"
            break
            ;;
        "[stats] Show query digest")
            query="SELECT hostgroup hg, sum_time, count_star, substr(digest_text,1,80) FROM stats_mysql_query_digest ORDER BY sum_time DESC LIMIT 15;"
            exec_query "$query"
            break
            ;;
        "[stats] Show hostgroups")
            query="SELECT hostgroup hg, SUM(sum_time), SUM(count_star) FROM stats_mysql_query_digest GROUP BY hostgroup;"
            exec_query "$query"
            break
            ;;

        "[log] Show connect")
            query="SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 10;"
            exec_query "$query"
            break
            ;;
        "[log] Show ping")
            query="SELECT * FROM monitor.mysql_server_ping_log ORDER BY time_start_us DESC LIMIT 10;"
            exec_query "$query"
            break
            ;;
        "[log] Show read_only")
            query="SELECT * FROM monitor.mysql_server_read_only_log ORDER BY time_start_us DESC LIMIT 10;"
            exec_query "$query"
            break
            ;;
        "[test][zaphod] sysbench prepare")
            cmd="sysbench --report-interval=5 --num-threads=4 --num-requests=0 --max-time=20 --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app1 --mysql-password=app1 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port prepare"
            exec_cmd "$cmd"
            break
            ;;
        "[test][zaphod] sysbench run - 15 sec, ro")
            cmd="sysbench --report-interval=1 --num-threads=4 --num-requests=0  --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app1 --mysql-password=app1 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port --oltp-read-only=on --mysql-ignore-errors=all  --max-time=15  run"
            exec_cmd "$cmd"
            break
            ;;
        "[test][zaphod] sysbench run - 60 sec, ro")
            cmd="sysbench --report-interval=1 --num-threads=4 --num-requests=0  --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app1 --mysql-password=app1 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port --oltp-read-only=on --mysql-ignore-errors=all  --max-time=60  run"
            exec_cmd "$cmd"
            break
            ;;

        "[HA][zaphod] MHA online failover (interactive)")
            cmd="masterha_master_switch --conf=/etc/mha/mha_damp_server_zaphod.cnf --master_state=alive --orig_master_is_new_slave --interactive=1"
            exec_cmd "$cmd"
            break
            ;;
        "[HA][zaphod] MHA online failover (noninteractive)")
            cmd="masterha_master_switch --conf=/etc/mha/mha_damp_server_zaphod.cnf --master_state=alive --orig_master_is_new_slave --interactive=0"
            exec_cmd "$cmd"
            break
            ;;
        "[test][zaphod] Split R/W")
            query="REPLACE INTO mysql_query_rules(rule_id,active,match_pattern,destination_hostgroup,apply) VALUES(1000,1,'^select',2,0);LOAD MYSQL QUERY RULES TO RUNTIME;SAVE MYSQL QUERY RULES TO DISK;\G"
            exec_query "$query"
            break
            ;;
        "[test][zaphod] Create 'world' sample db")
            cmd="wget -O /tmp/world.sql.gz http://downloads.mysql.com/docs/world.sql.gz"
            exec_cmd "$cmd"
            zcat  /tmp/world.sql.gz | mysql -h $host   --user=app1  --password=app1 --port $app_port
            break
            ;;
        "[test][arthurdent] sysbench prepare")
            cmd="sysbench --report-interval=5 --num-threads=4 --num-requests=0 --max-time=20 --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app3 --mysql-password=app3 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port prepare"
            exec_cmd "$cmd"
            break
            ;;
        "[test][arthurdent] sysbench run - 15 sec, ro")
            cmd="sysbench --report-interval=1 --num-threads=4 --num-requests=0  --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app3 --mysql-password=app3 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port --oltp-read-only=on --mysql-ignore-errors=all  --max-time=15  run"
            exec_cmd "$cmd"
            break
            ;;
        "[test][arthurdent] sysbench run - 60 sec, ro")
            cmd="sysbench --report-interval=1 --num-threads=4 --num-requests=0  --test=/usr/share/doc/sysbench/tests/db/oltp.lua --mysql-user=app3 --mysql-password=app3 --oltp-table-size=10000 --mysql-host=$host --mysql-port=$app_port --oltp-read-only=on --mysql-ignore-errors=all  --max-time=60  run"
            exec_cmd "$cmd"
            break
            ;;

        "[HA][arthurdent] MHA online failover (interactive)")
            cmd="masterha_master_switch --conf=/etc/mha/mha_damp_server_arthurdent.cnf --master_state=alive --orig_master_is_new_slave --interactive=1"
            exec_cmd "$cmd"
            break
            ;;
        "[HA][arthurdent] MHA online failover (noninteractive)")
            cmd="masterha_master_switch --conf=/etc/mha/mha_damp_server_arthurdent.cnf --master_state=alive --orig_master_is_new_slave --interactive=0"
            exec_cmd "$cmd"
            break
            ;;
        "[test][arthurdent] Split R/W")
            query="REPLACE INTO mysql_query_rules(rule_id,active,match_pattern,destination_hostgroup,apply) VALUES(1000,1,'^select',4,0);LOAD MYSQL QUERY RULES TO RUNTIME;SAVE MYSQL QUERY RULES TO DISK;\G"
            exec_query "$query"
            break
            ;;
        "[test][arthurdent] Create 'world' sample db")
            cmd="wget -O /tmp/world.sql.gz http://downloads.mysql.com/docs/world.sql.gz"
            exec_cmd "$cmd"
            zcat  /tmp/world.sql.gz | mysql -h $host   --user=app3  --password=app3 --port $app_port
            break
            ;;
         "Quit")
            exit
            ;;
         *) echo invalid option;;
        esac
    done
done
