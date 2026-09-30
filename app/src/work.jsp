<%@ page contentType="text/plain" %>
<%
  double acc = 0;
  for (int i = 1; i < 3_000_000; i++) acc += Math.sqrt(i) * Math.sin(i);
  out.print("done " + acc);
%>
