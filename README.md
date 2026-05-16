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

> TODO — to be documented

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
