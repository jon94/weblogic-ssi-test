
To increase the performance of the tunnel, consider installing NumPy. For instructions,
please see https://cloud.google.com/iap/docs/using-tcp-forwarding#increasing_the_tcp_upload_bandwidth

<%@ page contentType="application/json;charset=UTF-8" language="java" %>
{"status":"UP","app":"petclinic","server":"<%= application.getServerInfo() %>","java":"<%= System.getProperty("java.version") %>"}
