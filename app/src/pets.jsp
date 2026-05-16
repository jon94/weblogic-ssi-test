
To increase the performance of the tunnel, consider installing NumPy. For instructions,
please see https://cloud.google.com/iap/docs/using-tcp-forwarding#increasing_the_tcp_upload_bandwidth

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
