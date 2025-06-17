#!/bin/bash

echo "=== UPDATE SYSTEM ==="
sudo apt update && sudo apt upgrade -y

echo "=== SET HOSTNAME ==="
sudo hostnamectl set-hostname mailserver.local
echo "192.168.1.67 mailserver.local mailserver" | sudo tee -a /etc/hosts

echo "=== INSTALL POSTFIX ==="
echo "postfix postfix/mailname string mailserver.local" | sudo debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | sudo debconf-set-selections
sudo apt install postfix -y

echo "=== INSTALL DOVECOT ==="
sudo apt install dovecot-core dovecot-imapd dovecot-pop3d -y

echo "=== KONFIG DOVECOT ==="
sudo sed -i 's|^#*mail_location =.*|mail_location = mbox:~/mail:INBOX=/var/mail/%u|' /etc/dovecot/conf.d/10-mail.conf
echo "protocols = imap pop3" | sudo tee -a /etc/dovecot/dovecot.conf

echo "=== SET PERMISSION /var/mail ==="
sudo chmod 775 /var/mail
sudo chown root:mail /var/mail

echo "=== KONFIGURASI SASL POSTFIX ==="
sudo postconf -e 'smtpd_sasl_type = dovecot'
sudo postconf -e 'smtpd_sasl_path = private/auth'
sudo postconf -e 'smtpd_sasl_auth_enable = yes'
sudo postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination'
sudo postconf -e 'smtpd_tls_auth_only = yes'

echo "=== EDIT /etc/dovecot/conf.d/10-master.conf ==="
sudo sed -i '/^service auth {/,/^}/ s|^}|  unix_listener /var/spool/postfix/private/auth {\n    mode = 0660\n    user = dovecot\n    group = postfix\n  }\n}|' /etc/dovecot/conf.d/10-master.conf

echo "=== RESTART DOVECOT & POSTFIX ==="
sudo systemctl restart dovecot
sudo systemctl restart postfix

echo "=== INSTALL WEBMIN ==="
sudo apt install software-properties-common apt-transport-https wget -y
wget -qO - http://www.webmin.com/jcameron-key.asc | sudo apt-key add -
sudo add-apt-repository "deb http://download.webmin.com/download/repository sarge contrib"
sudo apt update
sudo apt install webmin -y
sudo systemctl enable webmin

echo "=== INSTALL APACHE, PHP, MARIADB ==="
sudo apt install apache2 php php-mysql mariadb-server unzip php-intl php-mbstring php-xml php-curl php-zip php-gd php-bcmath php-imagick -y

echo "=== DOWNLOAD DAN INSTALL RAINLOOP ==="
cd /var/www/html
sudo mkdir -p rainloop
cd rainloop
sudo wget http://www.rainloop.net/repository/webmail/rainloop-latest.zip
sudo unzip rainloop-latest.zip
sudo rm rainloop-latest.zip
sudo chown -R www-data:www-data /var/www/html/rainloop
sudo find /var/www/html/rainloop -type d -exec chmod 755 {} \;
sudo find /var/www/html/rainloop -type f -exec chmod 644 {} \;

echo "=== BUAT SELF-SIGNED SSL ==="
sudo mkdir -p /etc/ssl/mailserver
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/mailserver/mailserver.key \
  -out /etc/ssl/mailserver/mailserver.crt \
  -subj "/C=ID/ST=Local/L=Local/O=Local/OU=IT/CN=mailserver.local"

echo "=== KONFIGURASI APACHE UNTUK HTTPS ==="
sudo bash -c 'cat > /etc/apache2/sites-available/mailserver-ssl.conf <<EOF
<VirtualHost *:443>
    ServerName mailserver.local
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /etc/ssl/mailserver/mailserver.crt
    SSLCertificateKeyFile /etc/ssl/mailserver/mailserver.key

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF'

sudo a2enmod ssl
sudo a2ensite mailserver-ssl

echo "=== REDIRECT HTTP KE HTTPS ==="
sudo sed -i '/<\/VirtualHost>/i Redirect permanent / https://mailserver.local/' /etc/apache2/sites-available/000-default.conf

echo "=== RESTART APACHE ==="
sudo systemctl restart apache2

echo "=== ENABLE LAYANAN ==="
sudo systemctl enable postfix
sudo systemctl enable dovecot
sudo systemctl enable apache2
sudo systemctl enable mariadb
sudo systemctl enable webmin

echo "=== SELESAI ==="
echo "mailserver.local"
echo "📬 Webmail: https://mailserver.local/rainloop"
echo "🔧 Admin panel: https://mailserver.local:10000 (login: root atau sudo user)"
echo "👤 Tambah user dengan: sudo adduser namapengguna"
echo "sudo maildirmake.dovecot /home/user1/Maildir"
echo "sudo chown -R user1:user1 /home/user1/Maildir"
echo "🔑 RainLoop admin: https://mailserver.local/rainloop/?admin (user: admin, pass: 12345)"
