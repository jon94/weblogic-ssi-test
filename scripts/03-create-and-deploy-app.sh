#!/bin/bash
# Creates a simple WAR and deploys it to the Admin Server
# Run as oracle user after both servers are started

set -e
DOMAIN_HOME=/opt/oracle/domains/base_domain
MIDDLEWARE=/opt/oracle/middleware
JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
APP_DIR=/tmp/petclinic-build
WAR_PATH=/opt/oracle/apps/petclinic.war

mkdir -p ${APP_DIR}/WEB-INF ${APP_DIR}/css
mkdir -p /opt/oracle/apps

# --- index.jsp ---
cat > ${APP_DIR}/index.jsp << 'EOF'
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="java.util.*, java.net.InetAddress" %>
<!DOCTYPE html>
<html>
<head>
  <title>PetClinic on WebLogic</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; }
    h1   { color: #2c7a2c; }
    table { border-collapse: collapse; width: 100%; margin-top: 20px; }
    td, th { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
    th { background: #f0f0f0; }
    .tag { background:#2c7a2c; color:white; padding:2px 8px; border-radius:3px; font-size:12px; }
  </style>
</head>
<body>
  <h1>PetClinic <span class="tag">WebLogic 12.2.1.4</span></h1>
  <p>A simple app to generate HTTP traffic for Datadog SSI testing.</p>

  <h2>Endpoints</h2>
  <table>
    <tr><th>Path</th><th>Description</th></tr>
    <tr><td><a href="/petclinic/">/petclinic/</a></td><td>Home (this page)</td></tr>
    <tr><td><a href="/petclinic/pets">/petclinic/pets</a></td><td>List pets</td></tr>
    <tr><td><a href="/petclinic/owners">/petclinic/owners</a></td><td>List owners</td></tr>
    <tr><td><a href="/petclinic/health">/petclinic/health</a></td><td>Health check</td></tr>
  </table>

  <h2>Server Info</h2>
  <table>
    <tr><th>Property</th><th>Value</th></tr>
    <tr><td>Server</td><td><%= application.getServerInfo() %></td></tr>
    <tr><td>Java Version</td><td><%= System.getProperty("java.version") %></td></tr>
    <tr><td>Hostname</td><td><%= InetAddress.getLocalHost().getHostName() %></td></tr>
    <tr><td>Time</td><td><%= new Date() %></td></tr>
  </table>
</body>
</html>
EOF

# --- pets.jsp ---
cat > ${APP_DIR}/pets.jsp << 'EOF'
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="java.util.*" %>
<!DOCTYPE html>
<html>
<head><title>Pets - PetClinic</title>
<style>body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px;}
table{border-collapse:collapse;width:100%;}td,th{border:1px solid #ddd;padding:8px 12px;}th{background:#f0f0f0;}</style>
</head>
<body>
  <h1>Pets <a href="/petclinic/" style="font-size:14px">&larr; back</a></h1>
  <%
    String[][] pets = {
      {"1","Buddy","Dog","2019-03-15","George Franklin"},
      {"2","Luna","Cat","2021-07-22","Betty Davis"},
      {"3","Max","Hamster","2022-11-01","Harold Davis"},
      {"4","Whiskers","Cat","2020-05-10","Peter McTavish"},
      {"5","Rex","Dog","2018-09-30","Jean Coleman"}
    };
  %>
  <table>
    <tr><th>ID</th><th>Name</th><th>Type</th><th>Birth Date</th><th>Owner</th></tr>
    <% for(String[] p : pets) { %>
    <tr><td><%= p[0] %></td><td><%= p[1] %></td><td><%= p[2] %></td><td><%= p[3] %></td><td><%= p[4] %></td></tr>
    <% } %>
  </table>
</body></html>
EOF

# --- owners.jsp ---
cat > ${APP_DIR}/owners.jsp << 'EOF'
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head><title>Owners - PetClinic</title>
<style>body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px;}
table{border-collapse:collapse;width:100%;}td,th{border:1px solid #ddd;padding:8px 12px;}th{background:#f0f0f0;}</style>
</head>
<body>
  <h1>Owners <a href="/petclinic/" style="font-size:14px">&larr; back</a></h1>
  <%
    String[][] owners = {
      {"1","George Franklin","110 W. Liberty St.","Madison","6085551023"},
      {"2","Betty Davis","638 Cardinal Ave.","Sun Prairie","6085551749"},
      {"3","Harold Davis","2693 Commerce St.","McFarland","6085558763"},
      {"4","Peter McTavish","2387 S. Fair Way","Monona","6085552765"},
      {"5","Jean Coleman","105 N. Lake St.","Monona","6085552654"}
    };
  %>
  <table>
    <tr><th>ID</th><th>Name</th><th>Address</th><th>City</th><th>Phone</th></tr>
    <% for(String[] o : owners) { %>
    <tr><td><%= o[0] %></td><td><%= o[1] %></td><td><%= o[2] %></td><td><%= o[3] %></td><td><%= o[4] %></td></tr>
    <% } %>
  </table>
</body></html>
EOF

# --- health.jsp ---
cat > ${APP_DIR}/health.jsp << 'EOF'
<%@ page contentType="application/json;charset=UTF-8" language="java" %>
{"status":"UP","app":"petclinic","server":"<%= application.getServerInfo() %>","java":"<%= System.getProperty("java.version") %>"}
EOF

# --- web.xml ---
cat > ${APP_DIR}/WEB-INF/web.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<web-app version="3.1" xmlns="http://xmlns.jcp.org/xml/ns/javaee"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee http://xmlns.jcp.org/xml/ns/javaee/web-app_3_1.xsd">
  <display-name>PetClinic</display-name>
  <welcome-file-list>
    <welcome-file>index.jsp</welcome-file>
  </welcome-file-list>
  <servlet-mapping>
    <servlet-name>default</servlet-name>
    <url-pattern>/css/*</url-pattern>
  </servlet-mapping>
</web-app>
EOF

# Build WAR
echo "Building petclinic.war ..."
cd ${APP_DIR}
${JAVA_HOME}/bin/jar cvf ${WAR_PATH} .
echo "WAR created at ${WAR_PATH}"

# Deploy via WLST
cat > /tmp/deploy-app.py << PYEOF
connect('weblogic', 'Welcome1#', 't3://localhost:7001')
progress = deploy(
  appName   = 'petclinic',
  path      = '${WAR_PATH}',
  targets   = 'AdminServer,ssi-demo-ms',
  block     = 'true'
)
print('Deployment complete.')
disconnect()
PYEOF

echo "Deploying to WebLogic ..."
${MIDDLEWARE}/oracle_common/common/bin/wlst.sh /tmp/deploy-app.py

echo ""
echo "=== App deployed ==="
echo "  Admin Server:   http://$(hostname -I | awk '{print $1}'):7001/petclinic/"
echo "  Managed Server: http://$(hostname -I | awk '{print $1}'):7003/petclinic/"
echo "  Admin Console:  http://$(hostname -I | awk '{print $1}'):7001/console"
