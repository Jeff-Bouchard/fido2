#!/bin/bash
###############################################################
# /**
# * Copyright StrongAuth, Inc. All Rights Reserved.
# *
# * Use of this source code is governed by the GNU Lesser General Public License v2.1
# * The license can be found at https://github.com/StrongKey/fido2/blob/master/LICENSE
# */
###############################################################

# Keeping this here for testing
# Convert base64 input into usable config input
BASE64INPUT=$1
BASE64DECODED=$(echo -e "$BASE64INPUT" | base64 -d)
IFS=';' read -r -a args <<< "$BASE64DECODED"

DB_URL="${args[0]}"
DB_USER="${args[1]}"
DB_PASS="${args[2]}"
MARIA_SKFSDBUSER_PASSWORD="${args[3]}"

LDAP_URLPORT="${args[4]}"
LDAP_TYPE="${args[5]}"
LDAP_BINDDN="${args[6]}"
LDAP_PASS="${args[7]}"
LDAP_DNPREFIX="${args[8]}"
LDAP_DNSUFFIX="${args[9]}"
LDAP_BASEDN="${args[10]}"
LDAP_GROUPSUFFIX="${args[11]}"

# Start glassfish
echo "Starting glassfish..."
$GLASSFISH_HOME/bin/asadmin start-domain || { echo 'Failed to start domain' ; exit 1; }

# Configure AD
echo "Configuring Active Directory..."
cat >> $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties <<- EOFAPPCONF
appl.cfg.property.service.ce.ldap.ldaptype=$LDAP_TYPE
EOFAPPCONF
cat >> $STRONGKEY_HOME/skce/etc/skce-configuration.properties <<- EOFSKCECONF
ldape.cfg.property.service.ce.ldap.ldapurl=$LDAP_URLPORT
ldape.cfg.property.service.ce.ldap.ldaptype=$LDAP_TYPE
ldape.cfg.property.service.ce.ldap.ldapbinddn=$LDAP_BINDDN
ldape.cfg.property.service.ce.ldap.ldapbinddn.password=$LDAP_PASS
ldape.cfg.property.service.ce.ldap.ldapdnprefix=cn=
ldape.cfg.property.service.ce.ldap.ldapdnsuffix=,ou=users,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,dc=strongkey,dc=com
ldape.cfg.property.service.ce.ldap.basedn=$LDAP_BASEDN
ldape.cfg.property.service.ce.ldap.ldapgroupsuffix=,ou=groups,ou=v2,ou=SKCE,ou=StrongAuth,ou=Applications,dc=strongkey,dc=com
EOFSKCECONF

# Keystore tasks
echo "Performing keystore tasks..."
keytool -genkeypair -alias skfs -keystore $STRONGKEY_HOME/payara41/glassfish/domains/domain1/config/keystore.jks -storepass changeit -keypass changeit -keyalg RSA -keysize 2048 -sigalg SHA256withRSA -validity 3562 -dname "CN=*.strongkey.com,OU=\"StrongKey FidoServer\"" &&\
keytool -changealias -alias s1as -destalias s1as.original -keystore $STRONGKEY_HOME/payara41/glassfish/domains/domain1/config/keystore.jks -storepass changeit &&\
keytool -changealias -alias skfs -destalias s1as -keystore $STRONGKEY_HOME/payara41/glassfish/domains/domain1/config/keystore.jks -storepass changeit &&\
keytool -exportcert -alias s1as -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $STRONGKEY_HOME/payara41/glassfish/domains/domain1/config/keystore.jks -storepass changeit &>/dev/null
keytool -importcert -noprompt -alias $(hostname) -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $STRONGKEY_HOME/certs/cacerts -storepass changeit &>/dev/null
keytool -importcert -noprompt -alias $(hostname) -file $STRONGKEY_HOME/certs/$(hostname).der --keystore $STRONGKEY_HOME/payara41/glassfish/domains/domain1/config/cacerts.jks -storepass changeit &>/dev/null

# Configure DB
echo "Configuring database..."
$GLASSFISH_HOME/bin/asadmin create-jdbc-connection-pool --datasourceclassname org.mariadb.jdbc.MySQLDataSource --restype javax.sql.ConnectionPoolDataSource --isconnectvalidatereq=true --validationmethod meta-data --property ServerName=localhost:DatabaseName=skfs:port=3306:user=skfsdbuser:password=$MARIA_SKFSDBUSER_PASSWORD:DontTrackOpenResources=true SKFSPool
$GLASSFISH_HOME/bin/asadmin create-jdbc-resource --connectionpoolid SKFSPool jdbc/strongkeylite
$GLASSFISH_HOME/bin/asadmin set server.resources.jdbc-connection-pool.SKFSPool.max-pool-size=1000
$GLASSFISH_HOME/bin/asadmin set server.thread-pools.thread-pool.http-thread-pool.max-thread-pool-size=1000
$GLASSFISH_HOME/bin/asadmin set server.thread-pools.thread-pool.http-thread-pool.min-thread-pool-size=10
$GLASSFISH_HOME/bin/asadmin set resources.jdbc-connection-pool.SKFSPool.property.ServerName=$DB_URL
$GLASSFISH_HOME/bin/asadmin set resources.jdbc-connection-pool.SKFSPool.property.user=$DB_USER
$GLASSFISH_HOME/bin/asadmin set resources.jdbc-connection-pool.SKFSPool.property.password=$DB_PASS

# Treat the following as retrieving files from vault (mounting necessary to grab files)
# Remove when fidoserver on github is updated (currently commented for temp build from local)
rm /usr/local/strongkey/fidoserver.ear
wget https://demo4.strongkey.com/40ee4e53c08805ac5d101f389006c99c5ed0cef2a9b4044e1a1db5b626c41f9a/fidoserver.ear
wget https://github.com/StrongKey/fido2/raw/master/server/fidoserverInstall/signingkeystore.bcfks
wget https://github.com/StrongKey/fido2/raw/master/server/fidoserverInstall/signingtruststore.bcfks
mv signingkeystore.bcfks signingtruststore.bcfks $STRONGKEY_HOME/skfs/keystores

# Deploy fidoserver
echo "Deploying fidoserver..."
echo $(sha256sum $STRONGKEY_HOME/fidoserver.ear)
$GLASSFISH_HOME/bin/asadmin restart-domain || { echo 'Failed to restart domain' ; exit 1; }
$GLASSFISH_HOME/bin/asadmin deploy $STRONGKEY_HOME/fidoserver.ear || { echo 'Failed to deploy fidoserver' ; exit 1; }

# If custering arguments exist, set up clustering of the container
# No longer need to add hostnames to /etc/hosts file since hosts are in DNS
if [ ! -z "${args[12]}" ] ; then
	echo "Configuring container clustering"
	HOSTS="${args[12]}"
	SERVERID="${args[13]}"
	cat >> $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties <<- EOFAPPREPLCONF
appliance.cfg.property.serverid=$SERVERID
appliance.cfg.property.replicate=true
EOFAPPREPLCONF
	cat >> $STRONGKEY_HOME/skfs/etc/skfs-configuration.properties <<- EOFSKFSREPLCONF
skfs.cfg.property.replicate.hashmapsonly=true
EOFSKFSREPLCONF
	$GLASSFISH_HOME/bin/asadmin restart-domain
fi

# Remove config files after loading them into glassfish
rm $STRONGKEY_HOME/fidoserver.ear
rm $STRONGKEY_HOME/skfs/keystores/*.bcfks
rm -f $STRONGKEY_HOME/appliance/etc/appliance-configuration.properties $STRONGKEY_HOME/skce/etc/skce-configuration.properties $STRONGKEY_HOME/skfs/etc/skfs-configuration.properties

# Keeps the container running. Also helpful for debug.
tail -f /usr/local/strongkey/payara41/glassfish/domains/domain1/logs/server.log
