
To increase the performance of the tunnel, consider installing NumPy. For instructions,
please see https://cloud.google.com/iap/docs/using-tcp-forwarding#increasing_the_tcp_upload_bandwidth

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
    <tr><td><a href="/petclinic/pets.jsp">/petclinic/pets</a></td><td>List pets</td></tr>
    <tr><td><a href="/petclinic/owners.jsp">/petclinic/owners</a></td><td>List owners</td></tr>
    <tr><td><a href="/petclinic/health.jsp">/petclinic/health</a></td><td>Health check</td></tr>
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
