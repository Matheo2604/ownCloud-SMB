#!/bin/bash


# This script installs and configures ownCloud with Apache, MariaDB, and PHP7 on a Debian-based system.


# Clear the terminal and prompt the user for the ownCloud password and domain
clear
while true; do
    echo ''
    echo ''
    read -p "Domain or IP used to connect to ownCloud: " domain
    echo ''
    read -sp "Password to use for ownCloud: " owncloud_password
    echo ''
    read -sp "Repeat the password: " owncloud_password_verification
    echo ''
    if [ "$owncloud_password" = "$owncloud_password_verification" ]; then
        break
    fi    
done


# Update package lists and install necessary packages
apt-get update
apt-get -y install apache2 mariadb-server sudo curl gpg


# Add PHP repository and install PHP 7.4 and necessary extensions
apt-get -y install apt-transport-https lsb-release ca-certificates wget
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt-get update
apt-get -y install php7.4-{xml,intl,common,json,curl,mbstring,mysql,gd,imagick,zip,opcache,redis,apcu} libapache2-mod-php7.4 php7.4 redis


# Add ownCloud repository and install ownCloud
cd /var/www/
wget https://download.owncloud.com/server/stable/owncloud-complete-latest.tar.bz2 && \
tar -xjf owncloud-complete-latest.tar.bz2 && \
chown -R www-data. owncloud

# Configure Apache
cat > /etc/apache2/sites-available/owncloud.conf << 'EOL'
<VirtualHost *:80>
	ServerName {domain}
	Redirect permanent / https://{domain}
</VirtualHost>

<VirtualHost *:443>
	ServerName {domain}

	DocumentRoot /var/www/owncloud
	Alias / "/var/www/owncloud/"

	ErrorLog ${APACHE_LOG_DIR}/owncloud_error.log
	CustomLog ${APACHE_LOG_DIR}/owncloud_access.log combined

      <IfModule mod_headers.c>
             Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
      </IfModule>

	SSLEngine on
	SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
	SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

	<Directory /var/www/owncloud/>
		Options +FollowSymlinks
		AllowOverride All
		<IfModule mod_dav.c>
			Dav off
		</IfModule>
		SetEnv HOME /var/www/owncloud
		SetEnv HTTP_HOME /var/www/owncloud
	</Directory>
</VirtualHost>
EOL

sed -i "s/{domain}/$domain/g" /etc/apache2/sites-available/owncloud.conf


# Create the selfsigned certificate to have a basic security
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt << EOT
NA
NA
NA
NA
NA
NA
NA
EOT

# Restart apache to take in charge the new configuration
a2enmod ssl
a2enmod headers
a2ensite owncloud.conf
a2dissite 000-default.conf
a2enmod rewrite mime unique_id
apachectl -t


# Setup MariaDB
mysql --password=$owncloud_password --user=root --host=localhost << eof
  create database ownclouddb;
  grant all privileges on ownclouddb.* to root@localhost identified by "$owncloud_password";
  flush privileges;
  quit
eof


# Setup ownCloud database
cd /var/www/owncloud
sudo -u www-data php occ maintenance:install \
   --database "mysql" \
   --database-name "ownclouddb" \
   --database-user "root"\
   --database-pass "$owncloud_password" \
   --data-dir "/var/www/owncloud/data" \
   --admin-user "admin" \
   --admin-pass "$owncloud_password"


# Setup occ in the binairie folder
FILE="/usr/local/bin/occ"
cat <<EOM >$FILE
#! /bin/bash
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "\$@"
EOM
chmod +x $FILE


# Setup the trusted domain given by the user
occ config:system:set trusted_domains 1 --value="$domain"


# Setup memory caching to owncloud
occ config:system:set \
   memcache.local \
   --value '\OC\Memcache\APCu'
occ config:system:set \
   memcache.distributed\
   --value '\OC\Memcache\Redis'
occ config:system:set \
   memcache.locking \
   --value '\OC\Memcache\Redis'
occ config:system:set \
   redis \
   --value '{"host": "/var/run/redis/redis.sock", "port": "0"}' \
   --type json


# Setup of basic Firewall rules
apt-get install -y ufw
systemctl enable --now ufw
ufw allow "Apache Full"


# Setup basic cron task
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data


# Passing redis(mod for memory caching) from tcp to sock
/usr/sbin/usermod -G redis -a www-data
mkdir -p /var/run/redis/
chown -R redis:www-data /var/run/redis
sudo sed -i 's/^\s*port\s\+.*/port 0/' /etc/redis/redis.conf
sudo sed -i 's|^\s*#\?\s*unixsocket\s\+.*|unixsocket /var/run/redis/redis.sock|' /etc/redis/redis.conf
sudo sed -i 's/^\s*#\?\s*unixsocketperm\s\+.*/unixsocketperm 770/' /etc/redis/redis.conf
systemctl restart redis


# Restart apache take in count the new configuration 
systemctl restart apache2


# Reminder of the username, password and domain
occ -V
echo "Your ownCloud is accessable under: admin"
echo "Your ownCloud is accessable under: "$owncloud_password
echo "Your ownCloud is accessable under: "$domain
echo "The Installation is complete."
echo ''
exit 0
