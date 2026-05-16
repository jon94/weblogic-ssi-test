#!/bin/bash
# Start WebLogic Admin Server and Managed Server
# Run as oracle user

DOMAIN_HOME=/opt/oracle/domains/base_domain
MIDDLEWARE=/opt/oracle/middleware

# Boot identity file so servers don't prompt for credentials
mkdir -p ${DOMAIN_HOME}/servers/AdminServer/security
cat > ${DOMAIN_HOME}/servers/AdminServer/security/boot.properties << EOF
username=weblogic
password=Welcome1#
EOF

mkdir -p ${DOMAIN_HOME}/servers/ssi-demo-ms/security
cat > ${DOMAIN_HOME}/servers/ssi-demo-ms/security/boot.properties << EOF
username=weblogic
password=Welcome1#
EOF

echo "Starting Admin Server..."
nohup ${DOMAIN_HOME}/startWebLogic.sh > /tmp/adminserver.log 2>&1 &
echo "Admin Server PID: $!"

echo "Waiting 60s for Admin Server to be ready..."
sleep 60

echo "Starting Managed Server (ssi-demo-ms)..."
nohup ${DOMAIN_HOME}/bin/startManagedWebLogic.sh ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &
echo "Managed Server PID: $!"

echo ""
echo "Tail logs with:"
echo "  tail -f /tmp/adminserver.log"
echo "  tail -f /tmp/managed-ms.log"
