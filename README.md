# Docker-Anisble-Proxysql-MHA
Teaching them to play together

brew cask install docker
(you have to open docker from the applications and follow the steps, if you can execute 'docker ps' from a terminal, you are all set)
#this will install the server binaries as well, there is no cask for the client only 
brew install mysql 

docker pull percona
docker build -t damp . 
./mysql_start.sh
./ansible_start.sh

#connect to the new cluster as an 'app' (mysql-client -> ProxySQL -> MySQL instanes)
mysql -h 127.0.0.1 -u app  -pgempa -P 6033

#connect to the ProxySQL admin interface
mysql -h 127.0.0.1 -u admin  -padmin -P 6032
