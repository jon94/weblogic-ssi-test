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

> **Important:** Use dd-java-agent **v1.56.3** for WebLogic. Versions 1.61.0+ introduced a regression that causes WebLogic to crash due to a conflict between the Datadog JMX collector and WebLogic's MBean server. v1.56.3 is confirmed stable with JVM metrics working. See [SCP-1159](https://datadoghq.atlassian.net/browse/SCP-1159) for the upstream bug.

### Step 4b.1 — Install the Datadog Agent (if not already installed from SSI)

```bash
sudo DD_API_KEY=<YOUR_API_KEY> \
DD_SITE="datadoghq.com" \
DD_ENV=demo \
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
```

### Step 4b.2 — Download dd-java-agent v1.56.3

Do NOT use the generic `https://dtdg.co/latest-java-tracer` link — it downloads the latest version which crashes WebLogic. Download the specific version directly:

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

### Step 4b.3 — Add the agent to WebLogic's setDomainEnv.sh

`setDomainEnv.sh` is sourced before every server start and is the correct place to set JVM options for both Admin Server and Managed Server.

```bash
sudo bash -c 'printf "\n# Datadog Java Agent - manual instrumentation\nexport DD_SERVICE=petclinic\nexport DD_ENV=demo\nexport DD_AGENT_HOST=localhost\nJAVA_OPTIONS=\"\${JAVA_OPTIONS} -javaagent:/opt/datadog/dd-java-agent-1.56.3.jar\"\nexport JAVA_OPTIONS\n" >> /opt/oracle/domains/base_domain/bin/setDomainEnv.sh'
```

Verify it was added:
```bash
sudo tail -8 /opt/oracle/domains/base_domain/bin/setDomainEnv.sh
```

Expected output:
```
# Datadog Java Agent - manual instrumentation
export DD_SERVICE=petclinic
export DD_ENV=demo
export DD_AGENT_HOST=localhost
JAVA_OPTIONS="${JAVA_OPTIONS} -javaagent:/opt/datadog/dd-java-agent-1.56.3.jar"
export JAVA_OPTIONS
```

### Step 4b.4 — Restart WebLogic

```bash
# Kill existing servers and clear lock files
sudo ps aux | grep java | grep -v grep | awk '{print $2}' | xargs sudo kill -9 2>/dev/null
sudo find /opt/oracle/domains/base_domain/servers -name '*.lok' | xargs sudo rm -f 2>/dev/null
sudo find /opt/oracle/domains/base_domain/servers/AdminServer/data/store -type f | xargs sudo rm -f 2>/dev/null
sleep 3

# Start Admin Server
sudo rm -f /tmp/adminserver.log /tmp/managed-ms.log
sudo -u oracle nohup /opt/oracle/domains/base_domain/startWebLogic.sh > /tmp/adminserver.log 2>&1 &

# Wait for RUNNING
until grep -q 'Server state changed to RUNNING' /tmp/adminserver.log 2>/dev/null; do sleep 5; done
echo "Admin Server RUNNING"

# Start Managed Server
sudo -u oracle nohup /opt/oracle/domains/base_domain/bin/startManagedWebLogic.sh \
  ssi-demo-ms http://localhost:7001 > /tmp/managed-ms.log 2>&1 &

until grep -q 'Server state changed to RUNNING' /tmp/managed-ms.log 2>/dev/null; do sleep 5; done
echo "Managed Server RUNNING"
```

### Step 4b.5 — Verify agent loaded

```bash
sudo ps aux | grep weblogic | grep -v grep | grep 'dd-java-agent'
```

You should see `-javaagent:/opt/datadog/dd-java-agent-1.56.3.jar` in both the AdminServer and ssi-demo-ms processes.

### Step 4b.6 — Generate traffic and verify in Datadog

```bash
for i in {1..20}; do
  curl -s http://localhost:7001/petclinic/ > /dev/null
  curl -s http://localhost:7001/petclinic/pets.jsp > /dev/null
  curl -s http://localhost:7001/petclinic/owners.jsp > /dev/null
  curl -s http://localhost:7001/petclinic/health.jsp > /dev/null
done
```

Check **APM → Services → petclinic** for:
- Traces from all endpoints
- **JVM Metrics** tab (heap, GC, threads) — confirms JMX is working

### Known issues

| Issue | Cause | Fix |
|---|---|---|
| `BEA-000383` crash on startup | dd-java-agent 1.61.0+ JMX collector conflicts with WebLogic's MBeanServer | Use v1.56.3 |
| `Unable to obtain lock on AdminServer.lok` | Previous server crashed and left lock files | `sudo find /opt/oracle/domains -name '*.lok' \| xargs sudo rm -f` |
| `Cannot open file _WLS_ADMINSERVER000000.DAT` | Persistent store lock from crashed process | `sudo find .../servers/AdminServer/data/store -type f \| xargs sudo rm -f` |

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
