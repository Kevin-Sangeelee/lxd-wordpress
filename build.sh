#!/bin/bash

# Lets define some variables.
export CONTAINER="wp-container"
export DB_NAME="wordpress"
export DB_USER="wpuser"
export DB_PASS='Rvz6shj2'
export HOST="blog.example.com"

# true = When done, ask user to set root password
export SET_ROOT_PASSWORD=true

# true = for LetsEncrypt SSL certificates
export SSL_LETSENCRYPT=false

# PHP version (5.6, 7.0, 7.1, 7.2, 7.3 or 7.4)
export PHP_VERSION="7.3"

# Local dev/testing variables
# true = for self-signed SSL certificates
export SSL_SELFSIGNED=true

# Where to store self-signed certs
export LOCAL_SSL_PATH="/etc/openssl/certs"

# Matching HOST domain, used in SSL Common Name (CN)
export DOMAIN="example.com"

# Avoid connection errors by allowing any host (only in local/testing)
export DB_ALLOW_ANY_HOST=true

#
# Nothing below this point should need to be modified.
#

# Create a default Debian container.
lxc launch 'images:debian/9' ${CONTAINER}

# Run a script in the container to pull in the required packages
# and configure Apache and MariaDB.
cat <<EOF| lxc exec ${CONTAINER} bash

echo "In container, phase 1"

# Add PHP PPA repository for Debian
# Install the SURY Repository Signing Key
#
apt-get -y install gnupg2 apt-transport-https lsb-release ca-certificates curl
curl -sSL -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

# Install the SURY Repository
#
sh -c 'echo "deb https://packages.sury.org/php/ stretch main" > /etc/apt/sources.list.d/php.list'

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
apt-get -y install apache2 php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-mbstring php${PHP_VERSION}-soap php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-mysql libphp-phpmailer mariadb-server mariadb-client iputils-ping exim4-daemon-light curl wget netcat

# Enable the required Apache modules.
#
a2enmod php${PHP_VERSION} rewrite ssl

# Fetch WordPress, extract and install to the default web root.
#
wget 'https://wordpress.org/latest.tar.gz' -O wordpress.tar.gz
rm -Rf /var/www/html/index.html wordpress 2>/dev/null
tar xvzf wordpress.tar.gz
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
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF_C

EOF


if [ "$DB_ALLOW_ANY_HOST" = true ]; then

  #Allow access from ANY host to DB
  cat <<EOF| lxc exec ${CONTAINER} bash
mysql <<EOF_C
CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF_C
EOF

fi


lxc config device add ${CONTAINER} http proxy \
      listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
lxc config device add ${CONTAINER} https proxy \
      listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443

if [ "$SSL_LETSENCRYPT" = true ]; then

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

EOF

else

  if [ "$SSL_SELFSIGNED" = true ]; then
  
    cat <<EOF| lxc exec ${CONTAINER} bash

echo "In container, phase 2 (generate self-signed certificate)"

mkdir -p ${LOCAL_SSL_PATH}

# Generate Certificate authority (CA)
#
openssl req -new -x509 -nodes -sha256 -days 1024 -newkey rsa:2048 -keyout ${LOCAL_SSL_PATH}/RootCA.key.pem -out ${LOCAL_SSL_PATH}/${DOMAIN}-RootCA.crt.pem -subj "/C=US/CN=${DOMAIN} Root CA"
openssl x509 -in ${LOCAL_SSL_PATH}/${DOMAIN}-RootCA.crt.pem -outform pem -out ${LOCAL_SSL_PATH}/RootCA.crt

# Generate extfile config file
#
cat <<EOF_C >${LOCAL_SSL_PATH}/config.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.${DOMAIN}
DNS.2 = ${DOMAIN}
EOF_C

# Generate self-signed certificate request
#
openssl req -new -nodes -newkey rsa:2048 -keyout ${LOCAL_SSL_PATH}/${DOMAIN}-PrivCertKey.pem -out ${LOCAL_SSL_PATH}/${DOMAIN}-CSR.pem -subj "/C=US/CN=${DOMAIN}"

# Generate self-signed certificate
#
openssl x509 -req -sha256 -days 1024 -in ${LOCAL_SSL_PATH}/${DOMAIN}-CSR.pem -CA ${LOCAL_SSL_PATH}/${DOMAIN}-RootCA.crt.pem -CAkey ${LOCAL_SSL_PATH}/RootCA.key.pem -CAcreateserial -extfile ${LOCAL_SSL_PATH}/config.ext -out ${LOCAL_SSL_PATH}/${DOMAIN}-SelfSignedCert.pem

# Modify the default-ssl site configuration to use our new
# certificate.
#
sed -e 's:^[ \t]*SSLCertificateFile.\+$:SSLCertificateFile\t${LOCAL_SSL_PATH}/${DOMAIN}-SelfSignedCert.pem:' \
    -e 's:^[ \t]*SSLCertificateKeyFile.\+$:SSLCertificateKeyFile\t${LOCAL_SSL_PATH}/${DOMAIN}-PrivCertKey.pem:' \
    -e 's:^[ \t]*#SSLCertificateChainFile.\+$:SSLCertificateChainFile\t${LOCAL_SSL_PATH}/${DOMAIN}-RootCA.crt.pem:' \
    /etc/apache2/sites-available/default-ssl.conf >/tmp/default-ssl.conf
cat /tmp/default-ssl.conf >/etc/apache2/sites-available/default-ssl.conf
rm /tmp/default-ssl.conf
EOF

  fi

fi

cat <<EOF| lxc exec ${CONTAINER} bash
# Give ownership of the web root files to the web server user.
#
chown -R www-data:www-data /var/www/html/
EOF

if [[ "$SSL_LETSENCRYPT" = true || "$SSL_SELFSIGNED" = true ]]; then
  cat <<EOF| lxc exec ${CONTAINER} bash
# Enable the SSL site, and restart Apache.
#
a2ensite default-ssl
EOF
fi

cat <<EOF| lxc exec ${CONTAINER} bash
  systemctl restart apache2
EOF

printf "\nDONE!\n\n"
if [ "$SSL_SELFSIGNED" = true ]; then
  printf "*-*-*-*-*-*-*-*-*-*-*
  NOTE: Don't forget to import CA certificate to your browser.
  
  Copy from container using 'pull', for example:
  lxc file pull %s%s/${DOMAIN}-RootCA.crt.pem ~/Downloads/
*-*-*-*-*-*-*-*-*-*-*\n" $CONTAINER $LOCAL_SSL_PATH
fi

if [ "$SET_ROOT_PASSWORD" = true ]; then
  lxc exec ${CONTAINER} passwd
fi

