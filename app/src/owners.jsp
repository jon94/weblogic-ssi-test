<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="org.apache.logging.log4j.LogManager" %>
<%@ page import="org.apache.logging.log4j.Logger" %>
<%
  Logger logger = LogManager.getLogger("petclinic.owners");
  logger.info("GET /owners.jsp - listing all owners for {}", request.getRemoteAddr());
%>
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
