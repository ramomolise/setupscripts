#If Roundcube gives "Internal Error" after HestiaCP installation, run this script to fix it.

chown -R hestiamail:hestiamail /etc/roundcube/
find /etc/roundcube/ -type f -iname "*php" -exec chmod 640 {} \;