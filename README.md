# Fortify docker demo

This repository contains example docker compose files and scripts to setup a working Fortify ScanCentral SAST/DAST/SSC demo environment using the [fortifydocker](https://hub.docker.com/repositories/fortifydocker) images.
It also includes optional Sonatype Nexus Repository, IQ Server and Jenkins setup for integrations. 

## Prerequisites

### Docker

Install the latest version of docker for your target o/s, e.g. ubuntu.

### fortify.license file

A working **fortify.license** file for SSC and ScanCentral SAST.
Place this file at the repository root.

### Dockerhub ***fortifydocker*** credentials

You will need Docker Hub credentials with access to the private images in the
[fortifydocker](https://hub.docker.com/u/fortifydocker) organisation.

### ScanCentral DAST licenses

If using ScanCentral DAST, you will also need ScanCentral DAST and ScanCentral DAST Sensor activation tokens that can be entered in Fortify LIM.

### Sonatype Nexus IQ Server license

A working **sonatype-license.lic** file for Sonatype Nexus IQ Server.
Place this file at the repository root.

## Environment preparation

Edit the `demo.env` file if you to select different versions of the images to be installed,
or change any of the default usernames or passwords.

## Docker Hub login

The images used in this demo (`fortifydocker/*`) are hosted in a private Docker Hub organisation, so you must
authenticate before pulling or starting the stack:

```bash
docker login
```

Enter your Docker Hub username and password or personal access token when prompted. Docker stores the resulting login
in its configured credential store, so no repository credentials file is required.

## Running the demo with Docker Compose

### 1. Create the external Docker network

The compose files expect an external network named `ftfydemo_net`:

```bash
docker network create ftfydemo_net
```

### 2. Set up TLS for Traefik

Traefik routes `lim.<yourdomain>` and `ssc.<yourdomain>` over HTTPS. Two options:

**Option A: Real DNS + Let's Encrypt (recommended if you control public DNS for a domain)**

Point DNS A records for your chosen hostnames (e.g. `lim.example.com`, `ssc.example.com`) at this host's
public IP, update the `Host()` rules in [lim/docker-compose.yml](lim/docker-compose.yml) and
[ssc/docker-compose.yaml](ssc/docker-compose.yaml) to match, and set a real contact address in `ACME_EMAIL` in
`demo.env`. Traefik is already configured (see the `traefik` service `command` in `docker-compose.yml`) to use the
TLS-ALPN-01 challenge, which only needs port `443` open — no port 80 required. Certificates are issued
automatically the first time each hostname is requested.

Each router gets its own single-hostname certificate, which Traefik selects using the SNI value sent by the client.
Some restrictive networks (hospital or hotel guest Wi-Fi, captive portals, filtering proxies) strip or rewrite SNI. When
that happens Traefik cannot tell which certificate to serve and falls back to a self-signed certificate, so browsers
report "connection is not private" or "this site may be impersonating...". To avoid this,
[traefik/dynamic_tls.yml](traefik/dynamic_tls.yml) defines a `defaultGeneratedCert` — a single multi-SAN certificate
covering every demo hostname that Traefik serves whenever SNI is missing or unrecognised.

Update the `main` and `sans` entries in that file to match your own hostnames. Every name listed must already resolve to
this host, because TLS-ALPN-01 validates each SAN individually and the whole certificate fails if any one of them
cannot be validated. Verify the fallback with a request that sends no SNI:

```bash
echo | openssl s_client -connect <this-host-ip>:443 2>/dev/null |
  openssl x509 -noout -subject -ext subjectAltName
```

Note that this only fixes certificate selection on the server. A network that blocks the domains outright, or that
performs TLS interception with its own certificate authority, still shows warnings; the issuer in the warning identifies
the intercepting proxy. That must be resolved by the network operator allowlisting the domains, and users should not
click through such warnings.

**Option B: Docker Desktop/local environment with mkcert**

Use [mkcert](https://github.com/FiloSottile/mkcert) to generate locally-trusted certificates instead:

```bash
# Debian/Ubuntu
sudo apt-get install -y mkcert libnss3-tools

# macOS
brew install mkcert nss

# Windows
choco install mkcert
```

Run the local setup script. It copies `demo.local.env.example` to the ignored `demo.local.env`, installs the local
mkcert CA, generates one certificate covering all demo hostnames, and creates `ftfydemo_net` if needed:

```bash
./scripts/setup-local.sh
```

The local hostnames use the reserved `.localhost` suffix and resolve to the loopback interface without public DNS or
hosts-file changes. Containers resolve the same names to Traefik through aliases in `docker-compose.local.yml`.

### 3. Start the stack

The quickest way to bring up the whole demo is the global start script. It runs the preflight checks (licenses,
secrets, DAST initialisation, the external network), starts every profile, and waits until each service reports
ready:

```bash
./start.sh                # production environment, all profiles
./start.sh --local        # local environment (demo.local.env + docker-compose.local.yml)
./start.sh --profile default --profile jenkins
```

Use `./stop.sh` to shut everything down again without losing data — see [Stop / clean up](#9-stop--clean-up).

> The local and production environments share one Compose project, so the scripts refuse to start a stack in one
> mode while it is already running in the other. Stop it first, then switch.

To manage individual services instead, use Compose directly:

```bash
# Start the base "default" profile (traefik, lim, ssc)
docker compose --env-file demo.env --profile default up -d

# Or start only specific profiles, e.g. traefik + lim + ssc
docker compose --env-file demo.env up -d traefik lim ssc
```

For the local Docker Desktop environment, include the local override and environment file in every direct Compose
command:

```bash
docker compose --env-file demo.local.env -f docker-compose.yml -f docker-compose.local.yml \
	--profile default up -d
```

When you first sign in to SSC at `https://<SSC_HOSTNAME>/`, use the demo account `admin` with password `admin`.
SSC prompts you to change this password on first login; for this demo, set it to `F0rtifyPassword!` before configuring
ScanCentral integrations.

### 4. Check status and logs

```bash
docker compose --env-file demo.env ps
docker compose --env-file demo.env logs -f lim
```

#### Recover after an AWS EC2 stop/start

After the instance is running and SSH is available, rerun Compose so services start in dependency order. Start the base
stack and SAST profile with:

```bash
docker compose --env-file demo.env --profile default --profile scsast up -d
```

If ScanCentral DAST was initialized, start it with `./scdast/manage.sh up`. Check `docker compose --env-file demo.env ps`
and wait for services with healthchecks to report `healthy` before troubleshooting application access. Docker's
automatic restart policies do not enforce Compose dependency ordering during an EC2 boot.

An EC2 stop/start can assign a different public IPv4 address unless the instance uses an Elastic IP. Update the DNS A
records for `SSC_HOSTNAME`, `SCANCENTRAL_SAST_CONTROLLER_HOSTNAME`, and `SCANCENTRAL_DAST_API_HOSTNAME` (when set) to
the instance's current public IP, then confirm they resolve correctly. Ensure the EC2 security group allows inbound
TCP 443. Do not use `docker compose down -v` for routine recovery; it removes named volumes containing persistent
application and database data.

### 5. Start ScanCentral SAST

The ScanCentral SAST profile starts SSC, the ScanCentral SAST Controller, and a Linux sensor:

```bash
docker compose --env-file demo.env --profile scsast up -d
docker compose --env-file demo.env ps scancentral-sast-controller scancentral-sast-sensor
```

The controller is available at `https://<SCANCENTRAL_SAST_CONTROLLER_HOSTNAME>/scancentral-ctrl/`.
Its public hostname is configured by `SCANCENTRAL_SAST_CONTROLLER_HOSTNAME` in `demo.env`; the corresponding DNS A
record must point to the Docker host so Traefik can obtain a Let's Encrypt certificate.

The controller and sensor require token files and an internal TLS truststore in `scsast/secrets/`. These are runtime
secrets and are ignored by git.

The sensor downloads SCA secure-coding rulepacks from OpenText SmartUpdate (`https://update.fortify.com`) on startup
and stores them in the `ftfydata_scsast_sensor` volume. Verify rulepacks are installed before running scans:

```bash
docker exec fortify-docker-demo-scancentral-sast-sensor-1 /app/sca/bin/fortifyupdate -showInstalledRules
```

New sensors initially appear in the **Unassigned Sensors Pool**. Assign the sensor to the controller's **Default Pool**
before submitting jobs without a `-pool` option; otherwise, those jobs remain pending because they are routed to the
Default Pool. Reassign the sensor after resetting the ScanCentral SAST controller data.

#### Configure the SSC shared secret

The controller reads the shared secret from `scsast/secrets/ssc-secret`. Retrieve it from the Docker host and enter
the exact value in the shared-secret field when configuring the ScanCentral SAST Controller in SSC:

```bash
sudo cat scsast/secrets/ssc-secret
```

In SSC, open **Administration > Configuration > ScanCentral SAST** and enter:

- **Controller URL:** `https://<SCANCENTRAL_SAST_CONTROLLER_HOSTNAME>/scancentral-ctrl/`
- **Shared secret:** the value retrieved from `scsast/secrets/ssc-secret`

Save the configuration, then recycle SSC:

```bash
docker compose --env-file demo.env restart ssc
docker compose --env-file demo.env ps ssc
docker compose --env-file demo.env logs --tail 100 ssc
```

The `ssc` service should show `healthy`. Restarting the container preserves SSC configuration because it is stored in
the `ftfydata_ssc` and `ftfydata_mysql` named volumes. Confirm the controller is still reachable with a valid TLS certificate:

```bash
set -a; source "${DEMO_ENV_FILE:-demo.env}"; set +a
curl -fsS -o /dev/null -w 'ScanCentral Controller HTTP %{http_code}\n' \
	"https://${SCANCENTRAL_SAST_CONTROLLER_HOSTNAME}/scancentral-ctrl/"
```

For a non-demo deployment, replace the initial value with a random secret, then restart the controller and update
the matching value in SSC:

```bash
openssl rand -base64 48 | tr -d '\n' | sudo tee scsast/secrets/ssc-secret >/dev/null
sudo chown 1111:1111 scsast/secrets/ssc-secret
sudo chmod 400 scsast/secrets/ssc-secret
docker compose --env-file demo.env --profile scsast up -d --force-recreate scancentral-sast-controller
```

Store the secret in an approved password manager or secrets manager. Do not put it in `demo.env`, compose files, or git.

#### Configure ScanCentral SAST clients

ScanCentral SAST clients authenticate to the controller with the client authentication token stored on the Docker host
at `scsast/secrets/client-auth-token`. Retrieve it securely:

```bash
sudo cat scsast/secrets/client-auth-token
```

On each Fortify ScanCentral SAST client, update its `client.properties` file with the retrieved value:

```properties
client_auth_token=<value from scsast/secrets/client-auth-token>
```

Keep this token in an approved password manager or secrets manager. If it is rotated, restart the controller and update
`client_auth_token` in every client configuration before submitting new scan jobs.

### 6. Start ScanCentral DAST

The `scdast` profile deploys the ScanCentral DAST API, Global Service, Utility Service, Fortify Connect, one fixed Linux
scanner, their supporting WISE and scanner datastore services, SSC, LIM, Traefik, and a shared PostgreSQL cluster. The
DAST management database uses its own database and runtime role in PostgreSQL. Future products must use separate
databases and roles rather than the DAST schema or credentials.

The 26.2 images use the available `26.2.ubi.9` tag. The shorter `26.2` tag does not exist in the Docker Hub repositories.

#### Prepare DNS, SSC, and LIM

Point the DNS A record for `SCANCENTRAL_DAST_API_HOSTNAME` at the Docker host. Traefik obtains the public certificate and
forwards traffic to the DAST API over the internal Docker network.

Wait for DNS to resolve before configuring DAST in SSC, then verify that Traefik is serving a trusted certificate:

```bash
set -a; source demo.env; set +a
getent hosts "$SCANCENTRAL_DAST_API_HOSTNAME"
curl -fsS -o /dev/null -w 'ScanCentral DAST API HTTP %{http_code}\n' \
	"https://${SCANCENTRAL_DAST_API_HOSTNAME}/"
```

If Traefik started before the DNS record existed, its first ACME request can fail and the API will use Traefik's
self-signed default certificate. After DNS resolves to this host, restart Traefik and repeat the trusted `curl` check:

```bash
docker compose --env-file demo.env restart traefik
```

Create or select an SSC service account and set `SSC_DAST_USERNAME` and `SSC_DAST_PASSWORD` in `demo.env`. In LIM,
install the DAST licenses, ensure the account named by `LIM_USERNAME` can validate licenses, and configure the pool named
by `LIM_POOL_NAME` with the password in `LIM_POOL_PASSWORD`. The configuration tool validates these credentials; LIM does
not expose pool creation through its REST API.

#### Create secrets

Generate the local database, service, and scanner secrets:

```bash
mkdir -p postgres/secrets scdast/secrets
umask 077
openssl rand -base64 36 | tr -d '\n' > postgres/secrets/postgres-admin-password
for name in database-password service-token core-datastore-password scanner-datastore-password twofa-master-token; do
	openssl rand -base64 36 | tr -d '\n' > "scdast/secrets/$name"
done

key_dir=$(mktemp -d)
ssh-keygen -q -t rsa -b 4096 -m PEM -N '' -f "$key_dir/fortifyconnect"
base64 -w0 "$key_dir/fortifyconnect" > scdast/secrets/fortifyconnect-private-key
base64 -w0 "$key_dir/fortifyconnect.pub" > scdast/secrets/fortifyconnect-public-key
rm -rf "$key_dir"
chmod 600 postgres/secrets/postgres-admin-password scdast/secrets/*
```

The complete secret inventory is described in [scdast/README.md](scdast/README.md). Secret and generated files are
ignored by git. The SSC and LIM credentials in `demo.env` are intentionally tracked for this demo only; use a secrets
manager or untracked environment file for non-demo deployments.

#### Initialize and start

Initialization is explicit. It starts PostgreSQL, LIM, and SSC, then uses
`fortifydocker/scancentral-dast-config:26.2.ubi.9` in `New` mode to create and migrate the DAST database:

```bash
./scdast/manage.sh init
./scdast/manage.sh up
docker compose --env-file demo.env --profile scdast ps
```

For the local Docker Desktop environment, point the management script at the local environment and Compose override:

```bash
export DEMO_ENV_FILE="$PWD/demo.local.env"
export SCDAST_COMPOSE_OVERRIDE="$PWD/docker-compose.local.yml"
./scdast/manage.sh init
./scdast/manage.sh up
docker compose --env-file demo.local.env -f docker-compose.yml -f docker-compose.local.yml \
	--profile scdast ps
```

An unchanged second `init` validates the stored manifest and exits without modifying the database. Normal `up` refuses
to start when the settings template or DAST version differs from the initialized manifest.

Verify the public route, component logs, scanner registration, and SSC integration:

```bash
set -a; source "${DEMO_ENV_FILE:-demo.env}"; set +a
curl -fsS -o /dev/null -w 'ScanCentral DAST API HTTP %{http_code}\n' \
	"https://${SCANCENTRAL_DAST_API_HOSTNAME}/"
docker compose --env-file demo.env logs --tail 100 scancentral-dast-api scancentral-dast-globalservice \
	scancentral-dast-utilityservice scancentral-dast-scannerservice
```

In SSC, confirm ScanCentral DAST connectivity and submit a small authorized smoke scan. Confirm that the fixed scanner
appears in the default scanner pool and can obtain a LIM lease.

Use `./scdast/manage.sh down` to stop DAST-owned services while preserving SSC, LIM, the shared PostgreSQL cluster, and
all named volumes. Use `manage` for non-version configuration changes. Before an upgrade, back up the `scdast` database,
update the image version, and run:

```bash
./scdast/manage.sh upgrade --backup-complete
./scdast/manage.sh up
```

`./scdast/manage.sh reset --confirm` drops only the DAST database and role and removes generated runtime state. It does
not remove the shared PostgreSQL volume or databases belonging to other products.

This single-host deployment terminates public TLS at Traefik and uses HTTP between the trusted internal containers.
Production deployments should follow OpenText guidance for end-to-end TLS, component separation, backups, and external
secret management.

### 7. Start Sonatype Repository and Lifecycle

The optional `sonatype` profile adds Nexus Repository and Lifecycle (IQ Server). The `sonatype-integration` profile
also enables the locally built SSC integration service and its SSC dependencies. The supplied integration JAR 6.0.1
requires Java 17; the container runs with a maintained Temurin JRE as UID 1000.

Point `repo.onfortify.com`, `lifecycle.onfortify.com`, and `lifecycle2ssc.onfortify.com` at this host. These names are
configurable in `demo.env`. Traefik provides HTTPS on port 443; application, PostgreSQL, and IQ admin ports are not
published. Run:

```bash
./nexus/start.sh
# Local environment: run scripts/setup-local.sh first, then:
./nexus/start.sh --local
```

The script generates missing PostgreSQL/IQ database secrets, preserves existing credentials, creates only the
`iqserver` database and `iq` role, and leaves running shared services intact. It does not reset the DAST database.
Runtime IQ credentials and license files must be readable by UID 1000; keep `nexus/secrets/*` owned by that UID with
mode 600. Keep the secret files with database backups: regenerating them against an existing volume is not a reset.

The root `sonatype-license.lic` is mounted read-only and installed automatically when IQ is unlicensed. Check its
activation and expiry in Lifecycle; Repository Pro entitlement is separate and is not assumed. Repository uses its
own embedded database in the persistent `/nexus-data` volume.

- Repository: `https://repo.onfortify.com/`. On first sign-in, Repository prompts for the `admin` password stored
	inside the `nexus-repo` container at `/nexus-data/admin.password`. Retrieve it privately with
	`docker compose --env-file demo.env exec nexus-repo cat /nexus-data/admin.password`.
- Lifecycle: `https://lifecycle.onfortify.com/`. Default admin username is `admin` and default password is `admin123`.
	Change the password after your first login.

Change both initial passwords immediately, before public testing. In Lifecycle System Preferences, set the base URL
to `https://lifecycle.onfortify.com`. IQ needs outbound HTTPS to `clm.sonatype.com`. The pinned IQ release supports
PostgreSQL 14 and newer; the demo uses the existing 17.5 cluster. This single-host resource configuration is for
evaluation, not production sizing. Confirm free disk space and back up volumes before upgrades.

#### Configure SSC integration

Verify that the installed Sonatype SSC parser is enabled and compatible with this integration and SSC version. The
parser is a separate JAR from the integration service; the supplied metadata rulepack is not a substitute for it.

Create an SSC `CIToken` for an account with universal permission to upload analysis results, view application
versions, comment on issues, and suppress/unsuppress issues. Using a local editor, put the token in the ignored
`nexus/secrets/ssc-token` file, with mode 600 and ownership UID 1000. Do not put the token in `demo.env` or git.

Put the current IQ password in `nexus/secrets/iq-password` with the same ownership/permissions. Set `NEXUS_IQ_USERNAME`
to match the account. If the password file is absent, the start script creates the bootstrap `admin123` value; replace
it after rotating IQ credentials. Both secrets must be non-empty before integration can start.

Edit `nexus/nexus-iq-integration-service/files/mapping.json` to match real IQ application public IDs, evaluated stages,
and existing SSC application versions. The supplied entries are examples, not automatically created projects.
Configuration and mappings are mounted read-only. Integration work files and logs persist in a named volume.

```bash
./nexus/start.sh --integration
# Or for local testing:
./nexus/start.sh --local --integration
docker compose --env-file demo.env logs --tail 100 nexus-iq-integration-service
```

The integration uses `https://<NEXUS_IQ_HOSTNAME>` for IQ API calls because the same setting is embedded in the report
links uploaded to SSC; using the internal Docker hostname would create links that external SSC users cannot open. It
uses `http://ssc:8080/` internally for SSC, respecting `SSC_URL_PREFIX` when configured. Local mode mounts the mkcert
root CA into the integration container so Java trusts the local Traefik certificate. The integration polls every 15
minutes by default (`SONATYPE_POLL_INTERVAL_MINUTES`) and also accepts webhooks. A missing token deliberately blocks
integration startup without preventing Repository/Lifecycle from being used.

#### Configure the protected webhook

Only `POST https://lifecycle2ssc.onfortify.com/iqWebhook` is exposed. Other paths, including synchronization commands,
are not routed. `SONATYPE_WEBHOOK_ALLOWED_CIDRS` defaults to loopback only, blocking external requests. Replace it with
the comma-separated IQ egress and trusted tester CIDRs, then rerun the integration startup script. Check the actual
source address seen by Traefik; Docker NAT can differ from the container address. Do not allow the entire Docker
network or `0.0.0.0/0`. TLS alone does not authenticate webhook callers; the IP allowlist is required.

In Lifecycle **System Preferences > Webhooks**, create an enabled webhook with:

- **Event:** `Application Evaluation` only
- **URL (recommended):** `http://nexus-iq-integration-service:8182/iqWebhook`
- **Secret:** leave blank; this integration does not validate a webhook secret

The internal URL is recommended because IQ and the integration service share the Docker network. It avoids public DNS,
TLS, and proxy allowlist issues. The public alternative is `https://lifecycle2ssc.onfortify.com/iqWebhook`. Local
mkcert testing also needs its CA trusted by IQ when using the public HTTPS callback; the internal URL avoids that
requirement.

Re-evaluate one mapped application and watch the integration logs:

```bash
docker compose --env-file demo.env logs -f nexus-iq-integration-service
```

Successful delivery includes `Received webhook request`, followed by synchronization by report ID, and the refreshed
findings should arrive in SSC.
Verify that an unlisted external source receives 403 and `/startScanLoad` is not exposed. Polling and webhook tests
need a valid SSC token, IQ credentials, existing mappings, and the enabled parser; a healthy HTTP listener alone
does not demonstrate successful synchronization.

Stop only Sonatype-owned services without removing data or stopping SSC, DAST, PostgreSQL, or Traefik:

```bash
./nexus/stop.sh
# Local:
./nexus/stop.sh --local
```

For direct Compose use, prepare the secrets first and use `--profile sonatype` or `--profile sonatype-integration`.
The initializer also runs as a dependency of IQ in direct Compose startup. Never use `down -v` for routine recovery.
If a public image pull fails because of saved Docker credentials, refresh them with `docker login`; do not commit
registry credentials to the repository.

Reference: [IQ database configuration](https://help.sonatype.com/en/external-database-configuration.html),
[IQ configuration](https://help.sonatype.com/en/config-yaml.html), and
[Sonatype for Fortify SSC](https://help.sonatype.com/en/sonatype-fortify-ssc.html).

### 8. Start Jenkins and its build agent

The optional `jenkins` profile provides a Jenkins controller and one Linux build agent. The agent includes full
JDKs 17 and 21, Maven, Gradle wrapper support, Node.js 22 with npm, and the .NET 10 SDK. Builds run as the non-root
`jenkins` user. Neither service publishes host ports; the controller uses Traefik HTTPS and the agent connects over
WebSocket. There is no Docker socket access, Windows-only .NET Framework support, or preconfigured scan pipeline.
These services do not require Fortify images, licenses, or databases.

#### Start the controller

Set `JENKINS_HOSTNAME` in your environment file and point its DNS record at this host. The public default is
`jenkins.onfortify.com`. `JENKINS_VERSION` defaults to the rolling `lts-jdk21` tag; use an explicit compatible Jenkins
release tag for reproducible deployments. The agent base is digest-pinned in its Dockerfile; tool packages receive
current patches within their selected versions when the image is rebuilt without cache.

```bash
./jenkins/start.sh

# Local environment: rerun setup to include Jenkins in the TLS certificate
# and copy the public mkcert root CA for the agent.
./scripts/setup-local.sh
./jenkins/start.sh --local
```

Use either the public or local commands, not both against the same running stack. The scripts accept `DEMO_ENV_FILE`
to select a different environment file and work from any directory. Local mode uses `demo.local.env` and the local
Compose override. Existing local environment files need not be replaced: new settings have backward-compatible
defaults. Local Jenkins is available at `https://jenkins.ftfydemo.localhost/`.

On first startup, the script starts only Traefik and the controller, then stops successfully with registration
instructions because no agent secret exists yet. A direct controller-only startup is also supported:

```bash
docker compose --env-file demo.env --profile jenkins up -d traefik jenkins
```

On first boot, open `https://<JENKINS_HOSTNAME>/`. On the **Unlock Jenkins** screen, you must enter the initial admin
password stored inside the controller at `/var/jenkins_home/secrets/initialAdminPassword`. Retrieve it privately in
your terminal:

```bash
docker compose --env-file demo.env exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

For local direct Compose commands, replace `--env-file demo.env` with
`--env-file demo.local.env -f docker-compose.yml -f docker-compose.local.yml`.
Complete the secured setup wizard, create your administrator account, and set the Jenkins URL to the same HTTPS
address. Do not disable authentication. In **Manage Jenkins > Nodes > Built-In Node > Configure**, set the number of
executors to **0** so builds run on the dedicated agent rather than the controller.

#### Register and start the agent

In **Manage Jenkins > Nodes > New Node**, create a **Permanent Agent** with:

- Name: `build-agent`, matching `JENKINS_AGENT_NAME` if you override it.
- Remote root directory: `/home/jenkins/agent`.
- Executors: `1`.
- Labels: `linux java nodejs dotnet`.
- Usage: only build jobs with label expressions matching this node.
- Launch method: **Launch agent by connecting it to the controller**.

Save the node and open its page to retrieve its connection secret. Store the secret without adding it to an
environment file, a pipeline, or Git. The following commands prompt without echoing the value:

```bash
mkdir -p jenkins/secrets
chmod 700 jenkins/secrets
umask 077
read -r -s -p 'Agent secret: ' AGENT_SECRET; printf '\n'
printf '%s' "$AGENT_SECRET" > jenkins/secrets/agent-secret
unset AGENT_SECRET
chmod 600 jenkins/secrets/agent-secret
```

The file must be readable by container UID **1000**, including traversal of its parent directories. If your host user
has a different UID, arrange suitable ownership and restrictive permissions before continuing. The scripts do not
change ownership or print the secret automatically. Rerun `./jenkins/start.sh` (or `./jenkins/start.sh --local`) to build
and start the agent. Confirm **build-agent** is online in Jenkins; a running container alone is not proof that it
authenticated successfully. The connection uses verified HTTPS/WebSocket and requires no TCP port 50000 setting.

The local override mounts only `certs/mkcert-rootCA.pem` and supplies it to the Remoting client. Never copy or mount
the mkcert CA private key. This trusts local TLS for the agent connection; builds accessing other local HTTPS services
may require additional Java, Node.js, Git, or .NET certificate configuration. Do not bypass certificate validation.

#### Run builds

Use `agent { label 'java' }`, `agent { label 'nodejs' }`, or `agent { label 'dotnet' }` in your Jenkinsfile. Freestyle
jobs should use **Restrict where this project can be run** with the appropriate label. Install any job-specific Jenkins
plugins through the plugin manager; no application jobs or integration credentials are provisioned automatically.

Java builds default to JDK 21. `JAVA17_HOME` and `JAVA21_HOME` expose full compiler installations. For a JDK 17 Maven
build, use the following shell step; changing build `JAVA_HOME` does not change the agent's Java 21 Remoting runtime:

```bash
JAVA_HOME="$JAVA17_HOME" PATH="$JAVA17_HOME/bin:$PATH" ./mvnw -B verify
```

Use `mvn -B verify` for projects without a Maven wrapper, or `./gradlew --no-daemon build` for Gradle projects. Gradle
itself is selected by each project's wrapper, not a global installation. Typical Node.js and .NET steps are
`npm ci && npm test` and `dotnet test`. The .NET SDK is 10; projects requiring older runtime versions or a specific
`global.json` SDK need an appropriately extended agent image. Windows desktop workloads need a Windows agent.

`JENKINS_AGENT_NODE_MAJOR` and `JENKINS_AGENT_DOTNET_CHANNEL` select the agent's build arguments (defaults `22` and
`10.0`). JDK 17 and 21 are always installed. Rebuild the agent after changing these values. The pinned base can be
overridden using `docker compose ... build --build-arg AGENT_BASE_IMAGE=<compatible-image> jenkins-agent`.

The agent workspace persists in `ftfydata_jenkins_agent`; Maven, Gradle, npm, NuGet and .NET CLI caches persist in
`ftfydata_jenkins_agent_cache`. Caches can grow over time and are shared only within this dedicated agent. Explicit
project settings that override cache locations may bypass this persistence.

#### Status, shutdown and recovery

```bash
docker compose --env-file demo.env --profile jenkins ps jenkins jenkins-agent
docker compose --env-file demo.env logs --tail 100 jenkins-agent
./jenkins/stop.sh
# Local:
./jenkins/stop.sh --local
```

The stop script stops the agent first, then the controller, preserving their volumes and leaving Traefik and other
demo services running. Rerun the start script to recover. Agent name/secret mismatches or TLS errors leave it offline;
check its logs and node configuration. Back up Jenkins home before upgrading. Never use `down -v` for routine
shutdown. A prior standalone Jenkins deployment may use a differently project-prefixed volume: inspect and migrate
that data deliberately before switching, rather than deleting a conflicting container or attaching an empty volume.

### 9. Stop / clean up

Use `./stop.sh` for routine shutdowns, such as over a weekend. It stops every container gracefully but keeps all
containers, named volumes, and data intact, so `./start.sh` brings the stack back in the same state.

```bash
./stop.sh                 # graceful shutdown, data preserved
./stop.sh --local         # same, for the local environment
./stop.sh --force         # skip the confirmation prompt (required for cron and other non-interactive use)
```

Before stopping, let running Jenkins builds, SAST jobs, and DAST scans finish so they are not interrupted mid-write.
A full stop takes a few minutes: Nexus Repository and Lifecycle declare a 120s `stop_grace_period`, and the
`scdast-wise`, `scdast-wise-core`, and `scdast-twofa` containers do not respond to `SIGTERM`, so they run to the
`--timeout` (default 180s) before Docker kills them. This is expected and does not corrupt data.

Only use the commands below when you deliberately want to **destroy** the demo and start over. `down -v` deletes
every named volume, which means SSC findings, Nexus repositories, Lifecycle policies, and Jenkins job history are
permanently lost:

```bash
# Destructive: remove containers, named volumes, the network, and generated certs
docker compose --env-file demo.env --profile '*' down -v
docker network rm ftfydemo_net
rm -rf certs
```

---

Kevin A. Lee (kadraman) - klee2@opentext.com
