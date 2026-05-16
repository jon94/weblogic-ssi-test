#!/bin/bash
set -e
exec >> /var/log/startup-script.log 2>&1
echo "[$(date)] Starting setup..."

# Install JDK 1.8 and dependencies
dnf install -y java-1.8.0-openjdk-devel unzip wget curl

# Set JAVA_HOME system-wide
cat > /etc/profile.d/java.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
export PATH=$JAVA_HOME/bin:$PATH
EOF
chmod +x /etc/profile.d/java.sh

# Create oracle user and directories
useradd -m -d /home/oracle -s /bin/bash oracle 2>/dev/null || true
mkdir -p /opt/oracle/middleware /opt/oracle/domains /opt/oracle/installer
chown -R oracle:oracle /opt/oracle

echo "[$(date)] Setup complete. JDK installed, directories ready."
/usr/lib/jvm/java-1.8.0-openjdk/bin/java -version
