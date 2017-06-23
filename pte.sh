#!/bin/bash

##########################
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
nc='\033[0m' # No Color
container_prefix="damp_"
container_proxysql="damp_proxysql"
currdir=`pwd`
servers="$currdir/damp/hostfile"
playbook_config="damp/group_vars/all"
debug=0
pte_log="$currdir/pte.log"

usage()
{
	echo -ne "${yellow}$1${nc}\n"
	echo "usage $0 -c (reset|create|run|enter_container|proxysql_menu)"
    echo "example: "
    echo "$0 -c reset"
    echo "$0 -c create -n zaphod -s 3"
    echo "$0 -c create -n arthur -s 2 -t regular"
    echo "$0 -c run"
    exit 1
}

create()
{
	server_name=${container_prefix}server_$1
	num_of_servers=$2
	replication_type=${3:-gtid}
	touch $servers
	last_hostgroup=$(grep "hostgroup" $servers |tail -n 1 |cut -d":" -f 2 |sed 's/ //' )
	if [[ -z "$last_hostgroup" ]]
		then
			hostgroup=1
			echo -e "[proxysql]\nlocalhost\n\n" >>$servers
		else
			hostgroup=$(( $last_hostgroup + 2 ))
	fi


	list=$(docker ps -a --format '{{.Names}}'|grep -E "^${server_name}[0-9]{1,2}$")
	if [[ "$list" != "" ]]
	then
		echo "Containers with name: $server_name are already running, quit!"
		exit 1
	fi

	docker-ip() {
		local ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$@")
		echo $ip
	}



	echo -e "Starting the following containers in ${yellow}$server_name${nc} cluster(Repl:$replication_type):"
	for i in $(seq 1  $num_of_servers)
	do
		mkdir -p $currdir/mysql_hosts/${server_name}${i}/conf.d $currdir/mysql_hosts/${server_name}${i}/log_mysql
		if [ $i ==  "1" ]
		then
			sed   -e "s/server-id=/server-id=1/" -e "s/read_only=1/read_only=0/"  $currdir/my.cnf> $currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
		else
			sed   -e  "s/server-id=/server-id=${i}/"  $currdir/my.cnf> $currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
		fi

		if [ "$replication_type" == "gtid" ]
		then
			echo "gtid-mode=ON" >>$currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
			echo "enforce-gtid-consistency" >>$currdir/mysql_hosts/${server_name}${i}/conf.d/my.cnf
		fi

		cid=$(docker run --name ${server_name}${i} -h ${server_name}${i}  -d -v $currdir/mysql_hosts/${server_name}${i}/conf.d:/etc/mysql/conf.d -v $currdir/mysql_hosts/${server_name}${i}/log_mysql:/var/log/mysql  -e MYSQL_ROOT_PASSWORD=mysecretpass -d mysql:5.6)

		server_ip=$( docker-ip $cid )
		serverlist=("${serverlist[@]}" "$server_ip" )

		if [ $i ==  "1" ]
		then
			echo -e "${green}${server_name}${i}${nc}    ${cid:0:12} ($server_ip) (MASTER)"	
			master_ip=$server_ip
		else
			echo -e "+->${yellow}${server_name}${i}${nc} ${cid:0:12} ($server_ip) (SLAVE)"	
		fi

	done


	#waiting for the last server to be available
	isup=0
	echo -ne "\nWaiting for the ${yellow}${server_name}${num_of_servers}${nc} to be available"
	until [ $isup -eq "1" ]
	do
		isup=$(docker exec -ti ${server_name}${num_of_servers}  'mysql' -NB -uroot -pmysecretpass -e"select(234);" |grep "234" |wc -l )
		sleep 2
		echo -ne "."
	done
	echo -ne "${green}Done${nc}\n"
	echo -ne "Add replication user to the master ${green}${server_name}1${nc}"
	grant_output=$(docker exec -ti ${server_name}1  'mysql' -uroot -pmysecretpass -vvv -e "GRANT REPLICATION SLAVE ON *.* TO repl@'%' IDENTIFIED BY 'slavepass'\G")
	[ $debug -eq 1 ] && echo $grant_output>>$pte_log
	echo -ne "....${green}Done${nc}\n"
	#configure replication on all hosts

	
	for i in $(seq 2  $num_of_servers)
	do
		echo -ne "Setup and start replication on ${yellow}${server_name}${i}${nc}"
		if [ "$replication_type" == "gtid" ]
		then
		setup_slave_output=$(docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"change master to master_host='$master_ip',master_user='repl',master_password='slavepass',master_auto_position = 1;start slave;")
#		[ $debug -eq 1 ] && echo $setup_slave_output>>$pte_log
		else
		setup_slave_output=$(docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"change master to master_host='$master_ip',master_user='repl',master_password='slavepass',master_log_file='mysqld-bin.000004',master_log_pos=120;start slave;")
		[ $debug -eq 1 ] && echo $setup_slave_output>>$pte_log
		fi

		echo -ne "....${green}Done${nc}\n"

		if [ $debug -eq 1  ]
		then
			docker exec -ti ${server_name}${i}  'mysql' -uroot -pmysecretpass -e"SHOW SLAVE STATUS\G" -vvv 2>&1 >>$pte_log
		fi 
	done

	#update the ansible yml file with this cluster's data
	echo -e "[${server_name}]" >>$servers
	for item in ${serverlist[*]}
	do
		if [ "$item" == "$master_ip" ]
		then
			echo "$item mysql_role=master" >>$servers
		else
			echo "$item mysql_role=slave" >>$servers
		fi
	done
	echo -e "\n[${server_name}:vars]\ncluster=${server_name}\nhostgroup=$hostgroup\n" >>$servers

	echo -ne "\nCluster ${green}${server_name}${nc} is ready!\n"
}

reset()
{
	
	list=$(docker ps -a |grep ${container_prefix})
	if [[ "$list" != "" ]]
	then
	echo "Stopping and removing the following containers:"
		docker ps -a --format '{{.Names}}'|grep ${container_prefix}
		docker ps -a |grep ${container_prefix}|awk '{print $1 }'|xargs docker stop 2>&1>>$pte_log
		docker ps -a |grep ${container_prefix}|awk '{print $1 }'|xargs docker rm -f 2>&1>>$pte_log
		[ -d $currdir/mysql_hosts/ ] && rm -rf $currdir/mysql_hosts/
	else
	echo "No $container_prefix containers are running"
	fi
	rm -f $servers

}

run()
{
	if [ ! -f $servers ] 
	then
		echo -ne "${red}Error${nc}:No inventory file $servers exists, create some servers first with -c create\n"
		exit 1
	fi

	list=$(docker ps -a |grep "${container_proxysql}")
	if [[ "$list" != "" ]]
	then
		echo "Stopping and removing the existing ${container_proxysql} container"
		docker stop  ${container_proxysql}
		docker rm -v ${container_proxysql}
	fi
	docker run -p 3000:3000 -h proxysql_admin  -p 6032:6032 -p 6033:6033 -v `pwd`:/root/build --name ${container_proxysql} -t damp 
	#docker run -p 3000:3000  -p 6032:6032 -p 6033:6033 -v `pwd`:/root/build --name ${container_proxysql} -it mszel42/ansible-mha-proxysql-docker
	echo "Done" 
}

enter_container()
{
docker exec -it ${container_proxysql}  bash -c 'cd /root/build/damp/;/bin/bash '
}

proxysql_menu()
{
docker exec -it ${container_proxysql}  bash -c 'cd /root/build/damp/;/usr/local/bin/proxysql_menu.sh '
}


create_cluster()
{

type="gtid"
while [[ -z $name || -z $size || -z $type || $size -lt 2  ]]
do

    VALUES=$(dialog --ok-label "Submit" \
              --backtitle "Create MySQL cluster" \
              --output-separator ,  \
              --title "Create MySQL Clusters" \
              --form "Please fill the form below! $error"  15 50 0 \
          "Name:" 1 1 "$name"         1 14 20 18 \
          "Size:" 2 1 "$size"        2 14 2 1 \
          "gtid/regular" 3 1 "$type"       3 14 12 8 \
    3>&1 1>&2 2>&3)
    error="\nERROR: ALL FIELDS ARE MANDATORY AND SIZE MUST BE >1!"

    name=$(echo $VALUES |cut -d , -f 1)
    size=$(echo $VALUES |cut -d , -f 2)
    type=$(echo $VALUES |cut -d , -f 3)
done
create $name $size $type
}
#############START

numargs=$#
if [ $numargs -lt 2 ]; then

	if [ $(which dialog|wc -l) -eq 0 ]
	then
		usage 
	fi 

	menuitem=$(dialog --clear  --help-button --backtitle "Proxysql Test Environment" \
	--title "[ M A I N - M E N U ]" \
	--menu "You can use the UP/DOWN arrow keys, the first \n\
	letter of the choice as a hot key, or the \n\
	number keys 1-9 to choose an option.\n\
	Choose the TASK" 18 55 9 \
	reset    "Reset environment" \
	create  "Create MySQL cluster" \
	list	"List MySQL containers" \
	edit_config     "Edit global config" \
	run     "Run the Ansible playbook" \
	proxysql_menu "Run the menu driven test script" \
	enter_container "Login into the ProxySQL/HA container" \
	Exit "Exit to the shell" \
	3>&1 1>&2 2>&3)

	echo $menuitem

	case $menuitem in
		reset) reset ;;
		edit_config) dialog --editbox $playbook_config  60 70 2>${playbook_config}_new && mv ${playbook_config} ${playbook_config}_old && mv ${playbook_config}_new ${playbook_config} ;;
		create) create_cluster ;;
		list) dialog --backtitle "Proxysql Test Environment" --title "MySQL containers" --clear --msgbox "$(docker ps -a --format '{{.Names}}'|grep ${container_prefix} | grep -v ${container_proxysql} | sort -n|sed -e 's/\(.*[^1]$\)/+->\1/g')" 20 60  ;;
		run) run && docker logs damp_proxysql;;
		enter_container) enter_container ;;
		proxysql_menu) proxysql_menu ;;
		Exit) echo "Bye"; exit 0 ;;
	esac
	exec $0
fi



OPTIND=1
while getopts "c:n:s:t:"  OPT; do
  case $OPT in
    c)
        if [ "${OPTARG}" == "reset" -o "${OPTARG}" == "create" -o  "${OPTARG}" == "run" -o  "${OPTARG}" == "enter_container"  -o "${OPTARG}" == "proxysql_menu" ]
        then
                cmd=$OPTARG
        else
                echo "-c should be (reset|create|start|login|menu): $OPTARG is not a valid command"
                exit 1
        fi
      ;;
    n) 
		if [ "${cmd}" == "create" ]
        then
                name=$OPTARG
        else
                echo "-n name should be defined only when creating clusters (-c create) "
                exit 1
        fi
      ;;
    s) 
		if [ "${cmd}" == "create" ]
        then
			if [ $OPTARG -lt 2 ] 
			then
				usage "-s cluster size can't be less than 2" 
			fi 
            size=$OPTARG
        else
                echo "-s size should be defined only when creating clusters (-c create) "
                exit 1
        fi
      ;;
    t) 
		if [ "${cmd}" == "create" ]
        then
                type=$OPTARG
        else
                echo "-t replication_type(GTID|regular) should be defined only when creating clusters (-c create) "
                exit 1
        fi
      ;;

	esac
done
shift $((OPTIND-1))

if [ "$cmd" == "create" ]
then 
	if [ ! $name ]
	then
		usage "-n name should be defined" 
	elif [ ! $size ] 
	then
		usage "-s size  should be difined"
	fi
fi

echo "$cmd $name $size $type"
$cmd $name $size $type
#$0
