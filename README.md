# WebLogic 12.2.1.4 + Datadog SSI Test

Repro environment for testing Datadog Single Step Instrumentation (SSI) and manual Java agent instrumentation on WebLogic 12.2.1.4 running on RHEL 9.

## Environment

| | |
|---|---|
| **Cloud** | GCP (project: `datadog-ese-sandbox`, zone: `asia-east2-a`) |
| **OS** | RHEL 9 (`rhel-9` image family, `rhel-cloud`) |
| **Machine** | `e2-standard-4` (4 vCPU / 16GB RAM) |
| **JDK** | OpenJDK 1.8.0_492 (`java-1.8.0-openjdk-devel`) |
| **WebLogic** | 12.2.1.4.0 |
| **App** | Custom JSP WAR (`petclinic`) |
| **Ports** | 7001 (Admin Server), 7003 (Managed Server) |

## Repository Structure

```
.
├── gcp/
│   └── vm-startup.sh          # GCP VM startup script (installs JDK, creates oracle user)
├── scripts/
│   ├── 01-install-weblogic.sh # Silent WebLogic installer
│   ├── 02-create-domain.py    # WLST script to create domain + managed server
│   ├── 03-create-and-deploy-app.sh  # Builds petclinic WAR and deploys it
│   └── 04-start-servers.sh    # Starts Admin Server + Managed Server
└── app/
    └── src/                   # JSP source files for the petclinic app
```

---

## Step 1 — Create the GCP VM

```bash
# Firewall rule
gcloud compute firewall-rules create allow-weblogic \
  --project=datadog-ese-sandbox \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:7001,tcp:7003 \
  --target-tags=weblogic-server \
  --source-ranges=<YOUR_IP>/32

# VM
gcloud compute instances create weblogic-ssi-demo \
  --project=datadog-ese-sandbox \
  --zone=asia-east2-a \
  --machine-type=e2-standard-4 \
  --image-family=rhel-9 \
  --image-project=rhel-cloud \
  --boot-disk-size=60GB \
  --boot-disk-type=pd-ssd \
  --tags=weblogic-server \
  --metadata-from-file=startup-script=gcp/vm-startup.sh
```

SSH in via IAP:
```bash
gcloud compute ssh weblogic-ssi-demo \
  --project=datadog-ese-sandbox \
  --zone=asia-east2-a \
  --tunnel-through-iap
```

---

## Step 2 — Install WebLogic

WebLogic 12.2.1.4 requires the **Oracle JDK** check to be bypassed when using OpenJDK. The installer JAR must be patched to add `OpenJDK` to the `VM_TYPES` list in `oraparam.ini`.

Download the installer from Oracle:
> https://www.oracle.com/middleware/technologies/weblogic-server-installers-downloads.html
> File: `fmw_12.2.1.4.0_wls_lite_Disk1_1of1.zip`

Upload to VM:
```bash
gcloud compute scp fmw_12.2.1.4.0_wls_lite_Disk1_1of1.zip \
  weblogic-ssi-demo:/tmp/ \
  --project=datadog-ese-sandbox \
  --zone=asia-east2-a \
  --tunnel-through-iap
```

On the VM — patch the installer and install:
```bash
# Extract
mkdir -p /tmp/wls-patch
sudo mv /tmp/fmw_12.2.1.4.0_wls_lite_generic.jar /opt/oracle/installer/
sudo -u oracle /usr/lib/jvm/java-1.8.0-openjdk/bin/jar xf /opt/oracle/installer/fmw_12.2.1.4.0_wls_lite_generic.jar -C /tmp/wls-patch

# Patch oraparam.ini to allow OpenJDK
sudo chmod -R u+w /tmp/wls-patch
sudo find /tmp/wls-patch -name "oraparam.ini" \
  -exec sed -i "s/VM_TYPES=HotSpot,IBM/VM_TYPES=HotSpot,IBM,OpenJDK/" {} \;

# Repack with manifest preserved
sudo bash -c 'cd /tmp/wls-patch && /usr/lib/jvm/java-1.8.0-openjdk/bin/jar cfm /opt/oracle/installer/fmw_patched.jar META-INF/MANIFEST.MF .'
sudo chown oracle:oracle /opt/oracle/installer/fmw_patched.jar

# Install
sudo -u oracle bash /opt/oracle/scripts/01-install-weblogic.sh /opt/oracle/installer/fmw_patched.jar
```

> **Note:** The `-ignoreSysPrereqs` flag is required because GCP VMs have no swap space configured by default, which fails WebLogic's prerequisite check.

---

## Step 3 — Create Domain and Deploy App

```bash
# Create domain (Admin Server port 7001, Managed Server port 7003)
sudo -u oracle /opt/oracle/middleware/oracle_common/common/bin/wlst.sh \
  /opt/oracle/scripts/02-create-domain.py

# Start servers
sudo -u oracle nohup /opt/oracle/domains/base_domain/startWebLogic.sh \
  > /tmp/adminserver.log 2>&1 &

# Wait ~60s for Admin Server, then start Managed Server
sudo -u oracle nohup /opt/oracle/domains/base_domain/bin/startManagedWebLogic.sh \
  ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &

# Build and deploy petclinic WAR
sudo -u oracle bash /opt/oracle/scripts/03-create-and-deploy-app.sh
```

**Credentials:** `weblogic` / `Welcome1#`

**URLs:**
- App: `http://<VM_IP>:7001/petclinic/`
- Admin Console: `http://<VM_IP>:7001/console`

---

## Step 4a — Single Step Instrumentation (SSI)

```bash
# Install Datadog Agent with SSI enabled
sudo DD_API_KEY=<YOUR_API_KEY> \
DD_SITE="datadoghq.com" \
DD_APM_INSTRUMENTATION_ENABLED=host \
DD_ENV=demo \
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"

# Configure inject settings
sudo printf 'additional_environment_variables:\n  - key: DD_TRACE_SPLIT_BY_TAGS\n    value: servlet.context\n  - key: DD_ENV\n    value: demo\ninjection_rules:\n  - match_all: true\n    inject: force\n' \
  > /etc/datadog-agent/inject/host_config.yaml

# Restart agent and bounce WebLogic
sudo systemctl restart datadog-agent
sudo -u oracle nohup /opt/oracle/domains/base_domain/startWebLogic.sh > /tmp/adminserver.log 2>&1 &
# wait ~60s
sudo -u oracle nohup /opt/oracle/domains/base_domain/bin/startManagedWebLogic.sh \
  ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &
```

**Known issue:** WebLogic starts with its own internal `-javaagent` flags. SSI detects these as `other-java-agents` and blocks injection by default. The `inject: force` rule in `host_config.yaml` overrides this.

**`DD_TRACE_SPLIT_BY_TAGS=servlet.context`** — splits APM services by WAR context root so each deployed app appears as its own service in Datadog APM instead of a single generic JVM service.

### Uninstall SSI
```bash
sudo dd-host-install --uninstall
sudo systemctl restart datadog-agent
```

---

## Step 4b — Manual Java Agent Instrumentation

> **Tracer version:** Use dd-java-agent **v1.56.3** for WebLogic. Versions 1.61.0+ crash WebLogic due to a conflict between the Datadog JMX collector and WebLogic's internal MBeanServer. v1.56.3 is confirmed stable with full JVM metrics. See [SCP-1159](https://datadoghq.atlassian.net/browse/SCP-1159) for the upstream bug.

---

### Step 4b.1 — Create the Datadog directory

```bash
sudo mkdir -p /opt/datadog
```

---

### Step 4b.2 — Install the Datadog Agent

```bash
sudo DD_API_KEY=<YOUR_API_KEY> \
DD_SITE="datadoghq.com" \
DD_ENV=demo \
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

Verify the agent is running:
```bash
sudo datadog-agent status | grep -A3 "Agent \(v"
```

---

### Step 4b.3 — Configure the agent: UST, logs, and process check

#### 3a — Set env globally in datadog.yaml

```bash
sudo bash -c 'printf "\nenv: demo\n" >> /etc/datadog-agent/datadog.yaml'
```

> **Note:** Do NOT set `service` globally here. If you set `service` globally, process metrics will be double-tagged (once from the global tag, once from the process check). Set `service` only in the process check config (Step 3c).

#### 3b — Enable log collection

```bash
sudo bash -c 'printf "\nlogs_enabled: true\n" >> /etc/datadog-agent/datadog.yaml'
```

Create a WebLogic log source config:

```bash
sudo mkdir -p /etc/datadog-agent/conf.d/weblogic.d
sudo bash -c 'cat > /etc/datadog-agent/conf.d/weblogic.d/conf.yaml << EOF
logs:
  - type: file
    path: /opt/oracle/domains/base_domain/servers/AdminServer/logs/AdminServer.log
    service: petclinic
    source: weblogic
    env: demo
    tags:
      - server:AdminServer
      - version:1.0

  - type: file
    path: /opt/oracle/domains/base_domain/servers/AdminServer/logs/access.log
    service: petclinic
    source: weblogic
    sourcecategory: http_access
    env: demo
    tags:
      - server:AdminServer
      - version:1.0

  - type: file
    path: /opt/oracle/domains/base_domain/servers/ssi-demo-ms/logs/ssi-demo-ms.log
    service: petclinic
    source: weblogic
    env: demo
    tags:
      - server:ssi-demo-ms
      - version:1.0

  - type: file
    path: /opt/oracle/domains/base_domain/servers/ssi-demo-ms/logs/access.log
    service: petclinic
    source: weblogic
    sourcecategory: http_access
    env: demo
    tags:
      - server:ssi-demo-ms
      - version:1.0
EOF'
```

Make WebLogic log files readable by the dd-agent user:

```bash
sudo find /opt/oracle/domains/base_domain/servers/AdminServer/logs -name '*.log' -exec chmod o+r {} \;
sudo find /opt/oracle/domains/base_domain/servers/ssi-demo-ms/logs -name '*.log' -exec chmod o+r {} \;
sudo chmod o+rx /opt/oracle/domains/base_domain/servers/AdminServer/logs
sudo chmod o+rx /opt/oracle/domains/base_domain/servers/ssi-demo-ms/logs
sudo chmod o+rx /opt/oracle/domains/base_domain/servers/AdminServer
sudo chmod o+rx /opt/oracle/domains/base_domain/servers/ssi-demo-ms
sudo chmod o+rx /opt/oracle/domains/base_domain/servers
sudo chmod o+rx /opt/oracle/domains/base_domain
sudo chmod o+rx /opt/oracle/domains
```

#### 3c — Enable process collection and configure process check

Enable the process agent:

```bash
sudo bash -c 'printf "\nprocess_config:\n  process_collection:\n    enabled: true\n" >> /etc/datadog-agent/datadog.yaml'
```

Create the process check config to tag WebLogic processes with `service:petclinic`:

```bash
sudo mkdir -p /etc/datadog-agent/conf.d/process.d
sudo bash -c 'cat > /etc/datadog-agent/conf.d/process.d/conf.yaml << EOF
init_config:

instances:
  - name: weblogic-admin
    search_string: ["weblogic.Name=AdminServer"]
    exact_match: false
    service: petclinic

  - name: weblogic-managed
    search_string: ["weblogic.Name=ssi-demo-ms"]
    exact_match: false
    service: petclinic
EOF'
```

> The `search_string` matches against the full JVM command line. Using `weblogic.Name=AdminServer` uniquely identifies each WebLogic server process.

#### 3d — Restart the agent

```bash
sudo systemctl restart datadog-agent
```

Verify all checks are running:

```bash
sudo datadog-agent status 2>&1 | grep -E 'Process Agent|Status:|weblogic'
```

Expected: Process Agent `Running`, process check instances `[OK]`, all weblogic log sources `Status: OK`.

---

Unified Service Tagging (UST) requires `env`, `service`, and `version` to be consistent across the agent and the application. Set `env` on the agent so it matches what the tracer reports:

```bash
sudo bash -c 'printf "\nenv: demo\ntags:\n  - service:petclinic\n  - version:1.0\n" >> /etc/datadog-agent/datadog.yaml'
```

Verify:
```bash
sudo tail -5 /etc/datadog-agent/datadog.yaml
```

Expected:
```yaml
env: demo
tags:
  - service:petclinic
  - version:1.0
```

Restart the agent to apply:
```bash
sudo systemctl restart datadog-agent
```

---

### Step 4b.4 — Download dd-java-agent v1.56.3

> Do **not** use `https://dtdg.co/latest-java-tracer` — it downloads the latest version which crashes WebLogic. Always download the specific version from Maven.

```bash
sudo curl -Lo /opt/datadog/dd-java-agent-1.56.3.jar \
  https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/1.56.3/dd-java-agent-1.56.3.jar
```

Verify the download:
```bash
ls -lh /opt/datadog/dd-java-agent-1.56.3.jar
# Expected: ~32MB
```

---

### Step 4b.5 — Configure setDomainEnv.sh

`/opt/oracle/domains/base_domain/bin/setDomainEnv.sh` is sourced before every WebLogic server start. Adding the agent and UST tags here applies them to both the Admin Server and Managed Server automatically.

Append to the end of the file:
```bash
sudo bash -c 'printf "\n# Datadog Java Agent - manual instrumentation\nexport DD_SERVICE=petclinic\nexport DD_ENV=demo\nexport DD_VERSION=1.0\nexport DD_AGENT_HOST=localhost\nJAVA_OPTIONS=\"\${JAVA_OPTIONS} -javaagent:/opt/datadog/dd-java-agent-1.56.3.jar\"\nexport JAVA_OPTIONS\n" >> /opt/oracle/domains/base_domain/bin/setDomainEnv.sh'
```

Verify:
```bash
sudo tail -8 /opt/oracle/domains/base_domain/bin/setDomainEnv.sh
```

Expected:
```bash
# Datadog Java Agent - manual instrumentation
export DD_SERVICE=petclinic
export DD_ENV=demo
export DD_VERSION=1.0
export DD_AGENT_HOST=localhost
JAVA_OPTIONS="${JAVA_OPTIONS} -javaagent:/opt/datadog/dd-java-agent-1.56.3.jar"
export JAVA_OPTIONS
```

> **Why `setDomainEnv.sh`?** WebLogic's `startWebLogic.sh` and `startManagedWebLogic.sh` both source this file before launching the JVM. It is the single correct place to inject agent config — editing the start scripts directly is not recommended as they get regenerated by WebLogic tooling.

---

### Step 4b.6 — Restart WebLogic

```bash
# Stop all Java processes and clear lock/store files from previous run
sudo ps aux | grep java | grep -v grep | awk '{print $2}' | xargs sudo kill -9 2>/dev/null
sudo find /opt/oracle/domains/base_domain/servers -name '*.lok' | xargs sudo rm -f 2>/dev/null
sudo find /opt/oracle/domains/base_domain/servers/AdminServer/data/store -type f | xargs sudo rm -f 2>/dev/null
sleep 3

# Start Admin Server
sudo rm -f /tmp/adminserver.log /tmp/managed-ms.log
sudo -u oracle nohup /opt/oracle/domains/base_domain/startWebLogic.sh > /tmp/adminserver.log 2>&1 &

# Wait for RUNNING
until grep -q 'Server state changed to RUNNING' /tmp/adminserver.log 2>/dev/null; do sleep 5; done && echo "Admin Server RUNNING"

# Start Managed Server
sudo -u oracle nohup /opt/oracle/domains/base_domain/bin/startManagedWebLogic.sh \
  ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &

until grep -q 'Server state changed to RUNNING' /tmp/managed-ms.log 2>/dev/null; do sleep 5; done && echo "Managed Server RUNNING"
```

---

### Step 4b.7 — Verify agent is loaded in both JVMs

```bash
sudo ps aux | grep weblogic | grep -v grep | grep 'dd-java-agent'
```

You should see `-javaagent:/opt/datadog/dd-java-agent-1.56.3.jar` in **both** the `AdminServer` and `ssi-demo-ms` process lines.

---

### Step 4b.8 — Generate traffic

```bash
for i in {1..20}; do
  curl -s http://localhost:7001/petclinic/ > /dev/null
  curl -s http://localhost:7001/petclinic/pets.jsp > /dev/null
  curl -s http://localhost:7001/petclinic/owners.jsp > /dev/null
  curl -s http://localhost:7001/petclinic/health.jsp > /dev/null
done
```

---

### Step 4b.9 — Verify in Datadog

| What to check | Where |
|---|---|
| Traces with `env:demo`, `service:petclinic`, `version:1.0` | APM → Services → petclinic |
| JVM Metrics (heap, GC, threads) | APM → Services → petclinic → JVM Metrics |
| Unified Service Tagging across all signals | APM trace → click `env`, `service`, `version` tags to pivot to metrics/logs |

---

### Unified Service Tagging — nuances for WebLogic

Unified Service Tagging (UST) requires `env`, `service`, and `version` to be set **consistently in two places**. Missing either one means Datadog can't correlate traces, metrics, and logs under the same service identity.

#### 1. Agent-side (`/etc/datadog-agent/datadog.yaml`)

Sets the tags attached to all infrastructure metrics and host-level data reported by the agent:

```yaml
env: demo
tags:
  - service:petclinic
  - version:1.0
```

Restart the agent after editing: `sudo systemctl restart datadog-agent`

#### 2. JVM-side (`setDomainEnv.sh`)

Sets the tags attached to APM traces and JVM runtime metrics reported by the Java tracer:

```bash
export DD_SERVICE=petclinic
export DD_ENV=demo
export DD_VERSION=1.0
```

#### Why both are needed

| Tag source | What it affects |
|---|---|
| `datadog.yaml` | Infrastructure metrics, host tags, live processes |
| `DD_SERVICE/ENV/VERSION` in JVM | APM traces, JVM metrics, log correlation |

If you only set them on the JVM, infrastructure metrics won't share the same tags. If you only set them on the agent, traces won't carry `env`, `service`, and `version` — the **APM Service page will show the service but without version or env filtering**.

#### WebLogic-specific gotcha

WebLogic runs as two separate JVM processes (Admin Server and Managed Server). Because `setDomainEnv.sh` is sourced by both startup scripts, adding the `DD_*` exports there ensures **both JVMs** carry identical UST tags. If you set them only in the Admin Server's start script, the Managed Server's traces will be untagged.

#### Verify UST is working

```bash
# Confirm DD_ vars are set in both JVM processes
sudo cat /proc/$(pgrep -f 'weblogic.Name=AdminServer')/environ | tr '\0' '\n' | grep DD_
sudo cat /proc/$(pgrep -f 'weblogic.Name=ssi-demo-ms')/environ | tr '\0' '\n' | grep DD_
```

Both should show `DD_SERVICE=petclinic`, `DD_ENV=demo`, `DD_VERSION=1.0`.

In Datadog: open any trace in **APM → Traces**, click the `env`, `service`, or `version` tag — it should pivot seamlessly to metrics and logs with the same tag values.

---

### Known issues

| Issue | Cause | Fix |
|---|---|---|
| `BEA-000383` crash on startup | dd-java-agent 1.61.0+ JMX collector conflicts with WebLogic's MBeanServer | Use v1.56.3 |
| `Unable to obtain lock on AdminServer.lok` | Previous server crashed and left lock files | `sudo find /opt/oracle/domains -name '*.lok' \| xargs sudo rm -f` |
| `Cannot open file _WLS_ADMINSERVER000000.DAT` | Persistent store lock from crashed process | `sudo find .../servers/AdminServer/data/store -type f \| xargs sudo rm -f` |

### Known limitation — APM traces not generated for JSP requests

**Symptom:** Agent is loaded and connected, `dd.service`/`dd.env`/`dd.version` appear in logs via MDC, but `dd.trace_id`/`dd.span_id` are empty and no HTTP traces appear in APM for requests to JSP pages.

**Root cause:** WebLogic overrides the JVM system classloader with its own implementation:
```
-Djava.system.class.loader=com.oracle.classloader.weblogic.LaunchClassLoader
```
This custom classloader creates a classloader hierarchy that isolates the deployed application from the JVM bootstrap layer. The Datadog Java agent v1.56.3 instruments `javax.servlet.http.HttpServlet` to create HTTP spans, but because WebLogic's JSP engine loads compiled JSP servlets through the `LaunchClassLoader` hierarchy, the agent's bytecode instrumentation does not propagate into the application's request dispatch path.

**Impact:** JSP-based applications on WebLogic will not generate HTTP traces automatically with dd-java-agent v1.56.3. The agent IS loaded and connected (telemetry, JVM metrics, and profiler work correctly).

**What does work:**
- JVM metrics (heap, GC, threads) — visible in APM → Services → JVM Metrics
- Continuous Profiler — visible in APM → Profile Search
- WebLogic internal HTTP communication (e.g. Admin↔Managed Server) — does get traced
- MDC injection (`dd.service`, `dd.env`, `dd.version`) — populated in application logs

**What to tell customers:** Real-world applications deployed on WebLogic that use **Spring MVC**, **JAX-RS (Jersey/RESTEasy)**, or **Struts** go through framework-level dispatch mechanisms (`DispatcherServlet`, `Jersey`'s filter chain) that the Datadog agent instruments at a higher level — these will generate traces correctly. The limitation is specific to bare JSP/raw servlet applications without a framework layer.

---

## Restarting WebLogic

```bash
# Stop
sudo pkill -f weblogic.Server

# Start Admin Server
sudo rm -f /tmp/adminserver.log /tmp/managed-ms.log
sudo -u oracle nohup /opt/oracle/domains/base_domain/startWebLogic.sh > /tmp/adminserver.log 2>&1 &

# Wait for RUNNING
until grep -q 'Server state changed to RUNNING' /tmp/adminserver.log; do sleep 5; done

# Start Managed Server
sudo -u oracle nohup /opt/oracle/domains/base_domain/bin/startManagedWebLogic.sh \
  ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &
```

## Generate Traffic

```bash
for i in {1..20}; do
  curl -s http://localhost:7001/petclinic/ > /dev/null
  curl -s http://localhost:7001/petclinic/pets.jsp > /dev/null
  curl -s http://localhost:7001/petclinic/owners.jsp > /dev/null
done
```
