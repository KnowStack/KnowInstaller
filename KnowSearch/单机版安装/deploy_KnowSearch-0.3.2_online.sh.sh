#!/bin/bash
#set -x
function Install_Java(){
	if [ ! -d "/usr/local/java11" ];then
		cd $dir
		wget -O "jdk11.tar.gz" https://s3-gzpu.didistatic.com/pub/jdk11.tar.gz
	    tar -zxf $dir/jdk11.tar.gz -C /usr/local/
	    mv -f /usr/local/jdk-11.0.2 /usr/local/java11
	    echo "export JAVA_HOME=/usr/local/java11" >> ~/.bashrc
	    echo "export CLASSPATH=/usr/local/java11/lib" >> ~/.bashrc
	    echo "export PATH=\$JAVA_HOME/bin:\$PATH:\$HOME/bin" >> ~/.bashrc
	    source ~/.bashrc
	fi
}

function Install_Mysql(){
	while : 
		do
		read -p "Do you need to install MySQL(yes/no): " my_result
		if [ "$my_result" == "no" ];then
			which mysql >/dev/null 2>&1 
			if [ "$?" != "0" ];then
				echo "MySQL client is not installed on this machine. Start to install now"
				cd $dir
				wget -O "mysql5.7.tar.gz" https://s3-gzpu.didistatic.com/pub/mysql5.7.tar.gz
				mkdir -p $dir/mysql/ && cd $dir/mysql/
				tar -zxf $dir/mysql5.7.tar.gz -C $dir/mysql/
				rpm -ivh $dir/mysql/mysql-community-common-5.7.36-1.el7.x86_64.rpm
				rpm -ivh $dir/mysql/mysql-community-libs-5.7.36-1.el7.x86_64.rpm
				rpm -ivh $dir/mysql/mysql-community-client-5.7.36-1.el7.x86_64.rpm
			fi
			read -p "Please enter the MySQL service address: " mysql_ip
			read -p "Please enter MySQL service port(default is 3306): " mysql_port
			read -p "Please enter the root password of MySQL service: " mysql_pass
			if [ "$mysql_port" == "" ];then
				mysql_port=3306
			fi
			break
		elif [ "$my_result" == "yes" ];then
			read -p "Installing MySQL service will uninstall the installed(if any), Do you want to continue(yes/no): " option
			if [ "$option" == "yes" ];then	
				cd $dir
				wget -O "mysql5.7.tar.gz" https://s3-gzpu.didistatic.com/pub/mysql5.7.tar.gz
				rpm -qa | grep -E "mariadb|mysql" | xargs yum -y remove >/dev/null 2>&1 
				mv -f /var/lib/mysql/ /var/lib/mysqlbak$(date "+%s") >/dev/null 2>&1 
				mkdir -p $dir/mysql/ && cd $dir/mysql/
				tar -zxf $dir/mysql5.7.tar.gz -C $dir/mysql/
				yum -y localinstall mysql* libaio*
				sed -i "s#on-failure#always#g" /usr/lib/systemd/system/mysqld.service
				sed -i "/RestartPreventExitStatus=1/d" /usr/lib/systemd/system/mysqld.service
				sed -i "/Restart=always/a RestartSec=5" /usr/lib/systemd/system/mysqld.service
				systemctl daemon-reload
				systemctl start mysqld
				systemctl enable mysqld >/dev/null 2>&1 
				old_pass=`grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' | tail -n 1`
				mysql -NBe "alter user USER() identified by '$mysql_pass';" --connect-expired-password -uroot -p$old_pass
				if [ $? -eq 0 ];then
					mysql_ip="127.0.0.1"
					mysql_port="3306"
					echo  "Mysql database installation completed"
				else
					echo -e "${RED} Mysql database configuration failed. The script exits ${RES}"
					exit
				fi
				break
			else 
				exit 1
			fi
		else
			Printlog "Input error, please re-enter（yes/no）"
			continue
		fi
	done
}

function Install_ElasticSearch(){
	kill -9 $(ps -ef | grep elasticsearch | grep -v "grep" | awk '{print $2}')  >/dev/null 2>&1   
	id esuser  >/dev/null 2>&1  
	if [ "$?" != "0" ];then
		useradd esuser
		echo "esuser soft nofile 655350" >>/etc/security/limits.conf
		echo "esuser hard nofile 655350" >>/etc/security/limits.conf
		echo "vm.max_map_count = 655360" >>/etc/sysctl.conf
		sysctl -p >/dev/null 2>&1
	fi
	mkdir -p /know_es/es_data  && cd /know_es/ >/dev/null 2>&1
	wget -O "elasticsearch-v7.6.0.1400.tar.gz" https://s3-gzpu.didistatic.com/pub/elasticsearch-v7.6.0.1400.tar.gz
	tar -zxf elasticsearch-v7.6.0.1400.tar.gz -C /know_es/
	echo "cluster.max_shards_per_node: 12000" >> /know_es/elasticsearch-v7.6.0.1400/config/elasticsearch.yml
	sed -i "s#dc-cluster#logi-elasticsearch-meta#g" /know_es/elasticsearch-v7.6.0.1400/config/elasticsearch.yml
	chown -R esuser:esuser /know_es/
	su - esuser <<-EOF
		export JAVA_HOME=/usr/local/java11
		sh /know_es/elasticsearch-v7.6.0.1400/control.sh start
	EOF
	sleep 5
	es_status=`sh /know_es/elasticsearch-v7.6.0.1400/control.sh status | grep -o "started"`
	if [ "$es_status" = "started" ];then
		echo "elasticsearch started successfully～ "
	else
		echo -e "${RED} Elasticsearch failed to start. The script exited ${RES}"
		exit	
	fi
}


function Install_Nginx(){
	cd $dir
	wget -O "nginx-1.8.1.rpm" https://s3-gzpu.didistatic.com/pub/nginx-1.8.1.rpm
	rpm -ivh nginx-1.8.1.rpm  1>/dev/null 2>&1
	sed -i "s#user.*nginx#user  root#g" /etc/nginx/nginx.conf
	if [ $? -eq 0 ];then
		systemctl start nginx
		systemctl enable nginx 1&>/dev/null 2>&1
		echo "Nginx installation complete～"
	else
		echo "Nginx is already installed or failed to install"
	fi

}


function Install_Grafana(){
	cd $dir
	wget -O "grafana-8.5.9.tar.gz" https://s3-gzpu.didistatic.com/pub/knowsearch/grafana-8.5.9.tar.gz
	tar -zxf grafana-8.5.9.tar.gz -C $dir/
	sed -i "/User=user/d" $dir/grafana-8.5.9/bin/grafana.service
	sed -i "/Group=user/d" $dir/grafana-8.5.9/bin/grafana.service
	sed -i "s#dir_home#${dir}/grafana-8.5.9#g" $dir/grafana-8.5.9/bin/grafana.service
	cp $dir/grafana-8.5.9/bin/grafana.service /usr/lib/systemd/system/grafana.service
	systemctl daemon-reload
	systemctl start grafana
	sleep 10
	curl -X POST -H "Content-Type: application/json" "http://127.0.0.1:3000/api/datasources" -d '{"name":"elasticsearch-observability","type":"elasticsearch","url":"http://'$ip_addr':8060","access":"proxy","basicAuth":false,"database":"index_observability","jsonData":{"esVersion":"7.0.0","includeFrozen":false,"logLevelField":"","logMessageField":"","maxConcurrentShardRequests":5,"timeField":"logMills"},"readOnly":false}}' 
	for filename in $(ls $dir/grafana-8.5.9/template/)
	do
		echo
		curl  -H "Content-Type: application/json" -X POST "http://127.0.0.1:3000/api/dashboards/db" -d @$dir/grafana-8.5.9/template/$filename
	done
}

function Install_admin(){
 
    sed -i "s#mysql_pass#${mysql_pass}#g" $dir/KnowSearch-0.3.2/admin/application-full.yml
    sed -i "s#dir_home#${dir}/KnowSearch-0.3.2#g" $dir/KnowSearch-0.3.2/admin/control.sh 
    mysql -h$mysql_ip -uroot -p$mysql_pass -P$mysql_port -e "create database knowsearch"
    mysql -h$mysql_ip -uroot -p$mysql_pass -P$mysql_port knowsearch < $dir/KnowSearch-0.3.2/admin/init/init.sql
    sed -i "s#dir_home#${dir}/KnowSearch-0.3.2#g" $dir/KnowSearch-0.3.2/admin/arius-admin.service
    cp $dir/KnowSearch-0.3.2/admin/arius-admin.service /usr/lib/systemd/system/
    systemctl daemon-reload
    systemctl start arius-admin
    systemctl enable arius-admin 1>/dev/null 2>&1
    sleep 5
    sh $dir/KnowSearch-0.3.2/admin/init/init_knowsearch_linux.sh
    systemctl restart arius-admin

}

function Install_gateway(){
	sed -i "s#dir_home#${dir}/KnowSearch-0.3.2#g" $dir/KnowSearch-0.3.2/gateway/control.sh
    sed -i "s#dir_home#${dir}/KnowSearch-0.3.2#g" $dir/KnowSearch-0.3.2/gateway/arius-gateway.service
    sed -i "s#9200#8060#g" $dir/KnowSearch-0.3.2/gateway/log4j2.xml
    cp $dir/KnowSearch-0.3.2/gateway/arius-gateway.service /usr/lib/systemd/system/
    systemctl daemon-reload 
    systemctl start arius-gateway
    systemctl enable arius-gateway 1>/dev/null 2>&1
	cd $dir/KnowSearch-0.3.2/gateway/ && sh filebeats_start.sh 1>/dev/null 2>&1

}

function Install_console(){
	sed -i "s#c_path#${dir}/KnowSearch-0.3.2#g" $dir/KnowSearch-0.3.2/es/knowsearch_nginx.conf
	sed -i "s#ups_admin#127.0.0.1:8015#g" $dir/KnowSearch-0.3.2/es/knowsearch_nginx.conf
	sed -i "s#jumpToGrafana#http://$ip_addr:3000/dashboards#g"  $dir/KnowSearch-0.3.2/es/es-*.js
	cp $dir/KnowSearch-0.3.2/es/knowsearch_nginx.conf /etc/nginx/conf.d/
	nginx -s reload
}



function Install_KnowSearch(){
    cd $dir
    wget -O "KnowSearch-0.3.2.tar.gz" https://s3-gzpu.didistatic.com/pub/knowsearch/KnowSearch-0.3.2.tar.gz
    tar -zxf KnowSearch-0.3.2.tar.gz -C $dir/
    Install_admin
    Install_gateway
    Install_console

}


dir=`pwd`
RED='\E[1;31m'
RES='\E[0m'
#ip_addr=$(ifconfig `route|grep '^default'|awk '{print $NF}'`|grep inet|awk '{print $2}'|awk -F ':' '{print $NF}' | head -n 1)

mysql_pass=`date +%s |sha256sum |base64 |head -c 10 ;echo`"_Di2"
echo "$mysql_pass" > $dir/mysql.password
echo -e "${RED} The database password is stored in: $dir/mysql.password ${RES}"

echo 
echo "由于不同用户使用的网络环境不同，所以需要用户自行选择使用哪个IP作为访问IP"
echo "网络出口IP代表是该主机绑定的IP与出口IP不同，需要使用网络出口IP进行访问该主机，一般是云服务器"
echo "服务器网卡绑定的IP代表该IP即可以被外网访问也可以访问外网"
echo 
echo -e "${RED}1、Binding IP of local network card ${RES}"
echo -e "${RED}2、Network outlet IP ${RES}"
read -p "Use the outbound network IP or the IP bound by the local network card(1/2):" ip_addr
if [ "$ip_addr" == "1" ];then
	ip_addr=$(ifconfig `route|grep '^default'|awk '{print $NF}'`|grep inet|awk '{print $2}'|awk -F ':' '{print $NF}' | head -n 1)
elif [ "$ip_addr" == "2" ];then 
	ip_addr=$(curl -s  ipinfo.io | grep -w ip | awk -F":" '{print $2}' | sed 's/\"//g' | sed 's/,//g' | sed 's/^[ \t]*//g')
fi

Install_Mysql
Install_Java
Install_ElasticSearch
Install_Grafana
Install_Nginx
Install_KnowSearch
echo
echo "installation is complete"
echo

