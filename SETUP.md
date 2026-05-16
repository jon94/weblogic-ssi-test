# Datadog Setup for WebLogic 12.2.1.4

## Step 1 — Install the Datadog Agent

```bash
sudo DD_API_KEY=<YOUR_API_KEY> \
DD_SITE="datadoghq.com" \
DD_ENV=<YOUR_ENV> \
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

---

## Step 2 — Configure datadog.yaml

```bash
sudo bash -c 'printf "\nenv: <YOUR_ENV>\nlogs_enabled: true\n\nprocess_config:\n  process_collection:\n    enabled: true\n" >> /etc/datadog-agent/datadog.yaml'
```

> Do NOT set `service` globally here — set it only in the process check (Step 5).

---

## Step 3 — Download dd-java-agent v1.56.3

> ⚠️ Use v1.56.3. Do NOT use `https://dtdg.co/latest-java-tracer` — later versions crash WebLogic due to a JMX collector conflict with WebLogic's internal MBeanServer.

```bash
sudo mkdir -p /opt/datadog
sudo curl -Lo /opt/datadog/dd-java-agent-1.56.3.jar \
  https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/1.56.3/dd-java-agent-1.56.3.jar
```

Verify:
```bash
ls -lh /opt/datadog/dd-java-agent-1.56.3.jar
# Expected: ~32MB
```

---

## Step 4 — Add Java agent to setDomainEnv.sh

`setDomainEnv.sh` is sourced by both the Admin Server and Managed Server on startup. It is the correct place to inject the Java agent, Unified Service Tags, and profiler config for WebLogic.

> `DD_SERVICE` must be set here for APM traces. The process check `service` tag (Step 5) only tags process-level metrics — it does not affect the Java tracer.

```bash
sudo bash -c 'printf "\nexport DD_SERVICE=<YOUR_SERVICE>\nexport DD_ENV=<YOUR_ENV>\nexport DD_VERSION=<YOUR_VERSION>\nexport DD_AGENT_HOST=localhost\nexport DD_PROFILING_ENABLED=true\nJAVA_OPTIONS=\"\${JAVA_OPTIONS} -javaagent:/opt/datadog/dd-java-agent-1.56.3.jar\"\nexport JAVA_OPTIONS\n" >> /opt/oracle/domains/<YOUR_DOMAIN>/bin/setDomainEnv.sh'
```

Verify:
```bash
sudo tail -8 /opt/oracle/domains/<YOUR_DOMAIN>/bin/setDomainEnv.sh
```

---

## Step 5 — Process check config

Tags WebLogic JVM processes for process-level CPU/memory/disk I/O metrics in Datadog.

```bash
sudo mkdir -p /etc/datadog-agent/conf.d/process.d
sudo bash -c 'cat > /etc/datadog-agent/conf.d/process.d/conf.yaml << EOF
init_config:

instances:
  - name: weblogic-admin
    search_string: ["weblogic.Name=AdminServer"]
    exact_match: false
    service: <YOUR_SERVICE>

  - name: weblogic-managed
    search_string: ["weblogic.Name=<YOUR_MANAGED_SERVER_NAME>"]
    exact_match: false
    service: <YOUR_SERVICE>
EOF'
```

---

## Step 6 — Log collection config

```bash
sudo mkdir -p /etc/datadog-agent/conf.d/weblogic.d
sudo bash -c 'cat > /etc/datadog-agent/conf.d/weblogic.d/conf.yaml << EOF
logs:
  - type: file
    path: /opt/oracle/domains/<YOUR_DOMAIN>/servers/AdminServer/logs/AdminServer.log
    service: <YOUR_SERVICE>
    source: weblogic
    env: <YOUR_ENV>

  - type: file
    path: /opt/oracle/domains/<YOUR_DOMAIN>/servers/AdminServer/logs/access.log
    service: <YOUR_SERVICE>
    source: weblogic
    sourcecategory: http_access
    env: <YOUR_ENV>

  - type: file
    path: /opt/oracle/domains/<YOUR_DOMAIN>/servers/<YOUR_MANAGED_SERVER_NAME>/logs/<YOUR_MANAGED_SERVER_NAME>.log
    service: <YOUR_SERVICE>
    source: weblogic
    env: <YOUR_ENV>

  - type: file
    path: /opt/oracle/domains/<YOUR_DOMAIN>/servers/<YOUR_MANAGED_SERVER_NAME>/logs/access.log
    service: <YOUR_SERVICE>
    source: weblogic
    sourcecategory: http_access
    env: <YOUR_ENV>
EOF'
```

Fix permissions so dd-agent can read the log files:
```bash
sudo find /opt/oracle/domains/<YOUR_DOMAIN>/servers -name '*.log' -exec chmod o+r {} \;
sudo chmod o+rx /opt/oracle/domains/<YOUR_DOMAIN>/servers/AdminServer/logs
sudo chmod o+rx /opt/oracle/domains/<YOUR_DOMAIN>/servers/<YOUR_MANAGED_SERVER_NAME>/logs
sudo chmod o+rx /opt/oracle/domains/<YOUR_DOMAIN>/servers
sudo chmod o+rx /opt/oracle/domains/<YOUR_DOMAIN>
sudo chmod o+rx /opt/oracle/domains
```

---

## Step 7 — Enable Cloud Network Monitoring

Add to `datadog.yaml`:
```bash
sudo bash -c 'printf "\nnetwork_config:\n  enabled: true\n" >> /etc/datadog-agent/datadog.yaml'
```

Add to `system-probe.yaml`:
```bash
sudo bash -c 'printf "network_config:\n  enabled: true\n" >> /etc/datadog-agent/system-probe.yaml'
```

Enable and start the system probe:
```bash
sudo systemctl enable datadog-agent-sysprobe
sudo systemctl start datadog-agent-sysprobe
```

---

## Step 8 — Restart the agent

```bash
sudo systemctl restart datadog-agent
```

Verify:
```bash
sudo datadog-agent status 2>&1 | grep -E 'Process Agent|Status:|weblogic'
```

---

## Step 9 — Restart WebLogic

```bash
sudo -u oracle nohup /opt/oracle/domains/<YOUR_DOMAIN>/startWebLogic.sh > /tmp/adminserver.log 2>&1 &
until grep -q 'Server state changed to RUNNING' /tmp/adminserver.log 2>/dev/null; do sleep 5; done && echo "Admin Server RUNNING"

sudo -u oracle nohup /opt/oracle/domains/<YOUR_DOMAIN>/bin/startManagedWebLogic.sh \
  <YOUR_MANAGED_SERVER_NAME> http://localhost:7001 > /tmp/managed.log 2>&1 &
until grep -q 'Server state changed to RUNNING' /tmp/managed.log 2>/dev/null; do sleep 5; done && echo "Managed Server RUNNING"
```

---

## What you get in Datadog

| Signal | Where | Tags |
|---|---|---|
| APM Traces | APM → Services → `<YOUR_SERVICE>` | `env` `service` `version` |
| JVM Metrics | APM → Services → `<YOUR_SERVICE>` → JVM Metrics | `env` `service` |
| Continuous Profiler | APM → Profile Search | `env` `service` `version` |
| Logs | Logs → Explorer → `source:weblogic` | `service` `env` |
| Live Processes | Infrastructure → Processes | `service` |
| Network | NPM → Network Overview | host-level network flows |
