#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" && GIT_DIR=$(git rev-parse --show-toplevel)
source "${GIT_DIR}/scripts/GLOBAL_IMPORTS.sh"
source "${GIT_DIR}/configs/settings.sh"
source "${GIT_DIR}/configs/optional_software.sh"

PKGS+="nginx fcgiwrap spawn-fcgi mariadb "
PKGS_AUR+="multiwatch zoneminder "
_pkgs_add
_pkgs_aur_add

mkdir -p /etc/nginx/sites-enabled

SERVICES+="nginx.service fcgiwrap-multiwatch.service php-fpm.service zoneminder.service "
systemctl disable --now fcgiwrap.service fcgiwrap-multiwatch.service mariadb.service

systemd-tmpfiles --create

# Ensure the main conf file is present
_move2bkup "/etc/nginx/nginx.conf"
cp "${cp_flags}" "${GIT_DIR}"/files/etc/nginx/nginx.conf "/etc/nginx/"

# Enable ZoneMinder's server block if it's not already enabled
if [[ ! -f /etc/nginx/sites-enabled/zoneminder.conf ]]; then
    ln -sf /etc/nginx/sites-{available,enabled}/zoneminder.conf
fi

# Ensure MariaDB is installed
# Initialize MariaDB's default database if it's not already initialized
if [[ ! -d /var/lib/mysql/mysql ]]; then
    systemctl is-active --quiet mariadb && systemctl stop mariadb
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null
fi

systemctl enable --now mariadb.service

# Create ZoneMinder's database & user if they do not exist
if [[ ! -d "/var/lib/mysql/zm" ]]; then
    # Check for database root password
    if [[ "$(mysql -uroot -e "select * from mysql.user;" 2>&1)" = *"Access denied"* ]]; then
        # If a database root password is set
        echo "* Secure MariaDB installation found, please enter the database root password."
        echo
        mysql -uroot -p </usr/share/zoneminder/db/zm_create.sql
        echo
        echo "* Enter the password one more time..."
        echo
        mysql -uroot -p -e "grant select,insert,update,delete,create,drop,alter,index,lock tables,alter routine,create routine,trigger,execute on zm.* to 'zmuser'@localhost identified by 'zmpass';"
        echo
    else
        # If a database root password is not set
        mysql -uroot </usr/share/zoneminder/db/zm_create.sql
        mysql -uroot -e "grant select,insert,update,delete,create,drop,alter,index,lock tables,alter routine,create routine,trigger,execute on zm.* to 'zmuser'@localhost identified by 'zmpass';"
    fi
fi

_systemctl enable ${SERVICES}
