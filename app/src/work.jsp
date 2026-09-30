<%@ page contentType="text/plain" %>
<%
  // Loop count tuned in M7 against measured latency: 3,000,000 iterations
  // cost ~196 ms per request on a 1 vCPU app01, so one request was slower than
  // the 50-100 ms the load test wants. 1,000,000 measures ~65 ms here.
  double acc = 0;
  for (int i = 1; i < 1_000_000; i++) acc += Math.sqrt(i) * Math.sin(i);
  out.print("done " + acc);
%>
