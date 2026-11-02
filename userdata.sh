#!/bin/bash
dnf update -y
dnf install -y httpd wget php php-mysqlnd php-fpm php-json php-gd php-mbstring php-xml
systemctl enable --now httpd php-fpm

cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/

cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i "s|database_name_here|${db_name}|" wp-config.php
sed -i "s|username_here|${db_user}|" wp-config.php
sed -i "s|password_here|${db_password}|" wp-config.php
sed -i "s|localhost|${db_host}|" wp-config.php

chown -R apache:apache /var/www/html
systemctl restart httpd

