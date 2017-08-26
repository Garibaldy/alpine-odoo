#!/bin/bash

set -e

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the Odoo process if not present in the config file
: ${PSQL_HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PSQL_PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${PSQL_USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PSQL_PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

DB_ARGS=("--config=${ODOO_CONFIG}" "--logfile=${ODOO_LOG}")

ADDONS=("/usr/lib/python2.7/site-packages/openerp/addons" \
        "/usr/lib/python2.7/site-packages/odoo/addons" \
        "/opt/addons" \
        "/opt/odoo/addons" \
        "/mnt/addons" \
        )

# Check if there is a odoo.conf, if not create it
#if [ ! -f /etc/odoo/odoo.conf ]; then
if [ ! -f ${ODOO_CONFIG} ]; then
    echo "Configuration file not found!  Initializing docker volumes"
#    exec su-exec odoo odoo --save --config $ODOO_CONFIG 
#    echo "Disabling addons_path in the config file as we pass it as arguments"
#    sed -i '/addons_path/d' $ODOO_CONFIG
#    echo "Setting the database password and user"
#    sed -i '/^db_password =/s/=.*/= odoo/' $ODOO_CONFIG
#    sed -i '/^db_user =/s/=.*/= odoo/' $ODOO_CONFIG
#    echo "Setting the filestore directory"
#    sed -i 's/\/home\/odoo\/.local\/share\/Odoo/\/var\/lib\/odoo/g' $ODOO_CONFIG
	cp /root${ODOO_CONFIG} ${ODOO_CONFIG}
	chown odoo:odoo ${ODOO_CONFIG} 2>/dev/null
fi

# Install requirements.txt and oca_dependencies.txt from root of mount
if [[ "${SKIP_DEPENDS}" != "1" ]] ; then

    export VERSION=$ODOO_VERSION
    clone_oca_dependencies /opt/community /mnt/addons

    # Iterate the newly cloned addons & add into possible dirs
    for dir in /opt/community/*/ ; do
        ADDONS+=("$dir")
    done
	echo ${ADDONS[*]}
    VALID_ADDONS="$(get_addons ${ADDONS[*]})"
    DB_ARGS+=("--addons-path=${VALID_ADDONS}")

fi

# Pull database from config file if present & validate
function check_config() {
    param="$1"
    value="$2"
    if ! grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_CONFIG" ; then
        DB_ARGS+=("--${param}")
        DB_ARGS+=("${value}")
   fi;
}
check_config "db_host" "$PSQL_HOST"
check_config "db_port" "$PSQL_PORT"
check_config "db_user" "$PSQL_USER"
check_config "db_password" "$PSQL_PASSWORD"

# Change ownership to odoo for Volume and OCA
chown -R odoo:odoo \
	${ODOO_CONFIG_DIR} \
	${ODOO_LOG} \
	/var/lib/odoo \
	/opt/addons \
	/opt/community \
	/mnt/addons 2>/dev/null

# Big hack to fix ldap error from server-tools
#  ImportError: Error relocating /usr/local/lib/python2.7/site-packages/_ldap.so: ber_free: symbol not found
rm -rf /opt/community/server-tools/users_ldap_populate 2>/dev/null


# Execute
case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec su-exec odoo odoo "$@"
        else
            exec su-exec odoo odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        exec su-exec odoo odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        "$@"
esac

exit 1
