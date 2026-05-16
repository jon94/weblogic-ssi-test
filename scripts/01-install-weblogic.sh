#!/bin/bash
# Run as: oracle user
# Usage: ./01-install-weblogic.sh <path-to-installer.jar>
# Example: ./01-install-weblogic.sh /opt/oracle/installer/fmw_12.2.1.4.0_wls_lite_generic.jar

set -e
INSTALLER=${1:-/opt/oracle/installer/fmw_12.2.1.4.0_wls_lite_generic.jar}
ORACLE_HOME=/opt/oracle/middleware
JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk

if [ ! -f "$INSTALLER" ]; then
  echo "ERROR: Installer not found at $INSTALLER"
  echo "Upload the installer first: scp fmw_12.2.1.4.0_wls_lite_generic.jar oracle@<VM_IP>:/opt/oracle/installer/"
  exit 1
fi

# Create response file
cat > /tmp/wls_install.rsp << EOF
[ENGINE]
Response File Version=1.0.0.0.0

[GENERIC]
ORACLE_HOME=${ORACLE_HOME}
INSTALL_TYPE=WebLogic Server
EOF

# Create inventory pointer
cat > /tmp/oraInst.loc << EOF
inventory_loc=/opt/oracle/oraInventory
inst_group=oracle
EOF

echo "Installing WebLogic 12.2.1.4 to ${ORACLE_HOME} ..."
${JAVA_HOME}/bin/java -jar ${INSTALLER} \
  -silent \
  -responseFile /tmp/wls_install.rsp \
  -invPtrLoc /tmp/oraInst.loc

echo "WebLogic installation complete."
echo "ORACLE_HOME: ${ORACLE_HOME}"
ls ${ORACLE_HOME}/wlserver/
