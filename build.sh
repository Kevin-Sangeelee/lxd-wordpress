#!/bin/bash

# Lets define some variables.
export CONTAINER="wp-container"
export DB_NAME="wordpress"
export DB_USER="wpuser"
export DB_PASS="Rvz6shj2"
export HOST="blog.example.com"

#
# Nothing below this point should need to be modified.
#

# Create a default Debian container.
lxc launch 'images:debian/9' ${CONTAINER}

# Run a script in the container to pull in the required packages
# and configure Apache and MariaDB.
cat <<EOF| lxc exec ${CONTAINER} bash

echo "In container, phase 1"

apt-get update

# Generate some debconf parameters for Exim prior to the install.
#
cat <<EOF_C >exim_preseed.txt
exim4-config    exim4/dc_eximconfig_configtype  select internet site; mail is sent and received directly using SMTP
exim4-config    exim4/dc_localdelivery  select  mbox format in /var/mail/
exim4-config    exim4/dc_minimaldns     boolean false
exim4-config    exim4/no_config boolean true
exim4-config    exim4/use_split_config  boolean false
exim4-config    exim4/dc_relay_domains  string
exim4-config    exim4/mailname  string  ${HOST}
exim4-config    exim4/dc_postmaster     string
exim4-config    exim4/dc_local_interfaces       string  127.0.0.1 ; ::1
exim4-config    exim4/dc_relay_nets     string
exim4-config    exim4/hide_mailname     boolean
exim4-config    exim4/dc_readhost       string
exim4-config    exim4/dc_smarthost      string
EOF_C

debconf-set-selections exim_preseed.txt

# Install the required Debian packages.
#
apt-get -y install apache2 php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip libapache2-mod-php php-mysql libphp-phpmailer mariadb-server mariadb-client iputils-ping exim4-daemon-light curl wget netcat

# Enable the required Apache modules.
#
a2enmod rewrite ssl

# Fetch WordPress, extract and install to the default web root.
#
wget 'https://wordpress.org/wordpress-5.0.2.tar.gz'
rm -Rf /var/www/html/index.html wordpress 2>/dev/null
tar xvzf wordpress-5.0.2.tar.gz
mv wordpress/* /var/www/html/

cat <<EOF_C >/etc/apache2/conf-available/wordpress.conf
<FilesMatch \.php$>
  SetHandler application/x-httpd-php
</FilesMatch>

DirectoryIndex disabled
DirectoryIndex index.php index.html

<Directory /var/www/html/>
  Options -Indexes
  AllowOverride All
</Directory>
EOF_C

a2enconf wordpress

# Create a MariaDB database and user for WordPress.
#
mysql <<EOF_C
create database ${DB_NAME};
create user '${DB_USER}'@'localhost' identified by '${DB_PASS}';
grant all privileges on ${DB_NAME}.* to '${DB_USER}'@'localhost';
flush privileges;
EOF_C

EOF

lxc config device add ${CONTAINER} http proxy \
      listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
lxc config device add ${CONTAINER} https proxy \
      listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443

cat <<EOF| lxc exec ${CONTAINER} bash

echo "In container, phase 2"

# Fetch acme.sh to configure our Lets Encrypt certificate
# See acme.sh or https://github.com/Neilpang/acme.sh for
# details.
#
curl https://get.acme.sh | sh

# Generate a certificate using webroot authentication.
#
/root/.acme.sh/acme.sh --issue -d ${HOST} -w /var/www/html/

# Install the certificate artifacts in a directory for Apache
# to use.
#
mkdir -p /etc/letsencrypt/acme.sh
/root/.acme.sh/acme.sh --install-cert -d ${HOST} \
--cert-file      /etc/letsencrypt/acme.sh/cert.pem  \
--key-file       /etc/letsencrypt/acme.sh/key.pem  \
--fullchain-file /etc/letsencrypt/acme.sh/fullchain.pem \
--reloadcmd     "service apache2 force-reload"

# Modify the default-ssl site configuration to use our new
# certificate.
#
sed -e 's:^[ \t]*SSLCertificateFile.\+$:SSLCertificateFile\t/etc/letsencrypt/acme.sh/cert.pem:' \
    -e 's:^[ \t]*SSLCertificateKeyFile.\+$:SSLCertificateKeyFile\t/etc/letsencrypt/acme.sh/key.pem:' \
    -e 's:^[ \t]*#SSLCertificateChainFile.\+$:SSLCertificateChainFile\t/etc/letsencrypt/acme.sh/fullchain.pem:' \
    /etc/apache2/sites-available/default-ssl.conf >/tmp/default-ssl.conf
cat /tmp/default-ssl.conf >/etc/apache2/sites-available/default-ssl.conf
rm /tmp/default-ssl.conf

# Give ownership of the web root files to the web server user.
#
chown -R www-data:www-data /var/www/html/

# Enable the SSL site, and restart Apache.
#
a2ensite default-ssl

service apache2 restart

EOF

