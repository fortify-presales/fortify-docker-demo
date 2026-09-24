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

A working **sonatype.license** file for Sonatype Nexus IQ Server.
Place this file in the "files" directory of the project.

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

```bash
# Start everything in the "default" profile (traefik, lim, ssc, jenkins, jira, nexus, scancentral-sast, ...)
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

### 7. Stop / clean up

```bash
# Stop and remove containers
docker compose --env-file demo.env down

# Also remove named volumes, the network, and generated certs
docker compose --env-file demo.env down -v
docker network rm ftfydemo_net
rm -rf certs
```

---

Kevin A. Lee (kadraman) - klee2@opentext.com
