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

You will need Docker Hub credentials to access the private docker images in the [fortifydocker](https://hub.docker.com/u/fortifydocker) organisation. Please create a file called `demo.credentials` in the root directory
with contents similar to the following:

```
DOCKER_USERNAME=__YOUR_DOCKERHUB_USERNAME__
DOCKER_PASSWORD=__YOUR_DOCKERHUB_PASSWORD__
```

### ScanCentral DAST licenses

If using ScanCentral DAST, you will also need licenses that can be entered in Fortify LIM.

### Sonatype Nexus IQ Server license

A working **sonatype.license** file for Sonatype Nexus IQ Server.
Place this file in the "files" directory of the project.

## Environment preparation

Edit the `demo.env` file if you to select different versions of the images to be installed,
or change any of the default usernames or passwords.

## Docker Hub login

The images used in this demo (`fortifydocker/*`) are hosted in a private Docker Hub organisation, so you must
authenticate before pulling or starting the stack. Using the `demo.credentials` file created above:

```bash
# --password-stdin avoids exposing the password in your shell history or process list
set -a; source demo.credentials; set +a
echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
```

Or log in interactively without a credentials file:

```bash
docker login
```

## Running the demo with Docker Compose

### 1. Create the external Docker network

The compose files expect an external network named `ftfydemo_net`:

```bash
docker network create ftfydemo_net
```

### 2. Set up TLS for Traefik

Traefik routes `lim.<yourdomain>` and `ssc.<yourdomain>` over HTTPS. Two options:

**Option A: Real DNS + Let's Encrypt (recommended if you control public DNS for a domain)**

Point DNS A records for your chosen hostnames (e.g. `lim.onfortify.com`, `ssc.onfortify.com`) at this host's
public IP, update the `Host()` rules in [lim/docker-compose.yml](lim/docker-compose.yml) and
[ssc/docker-compose.yaml](ssc/docker-compose.yaml) to match, and set a real contact address in `ACME_EMAIL` in
`demo.env`. Traefik is already configured (see the `traefik` service `command` in `docker-compose.yml`) to use the
TLS-ALPN-01 challenge, which only needs port `443` open — no port 80 required. Certificates are issued
automatically the first time each hostname is requested.

**Option B: mkcert self-signed certs (local/offline use)**

Use [mkcert](https://github.com/FiloSottile/mkcert) to generate locally-trusted certificates instead:

```bash
# Debian/Ubuntu
sudo apt-get install -y mkcert libnss3-tools

# macOS
brew install mkcert nss

# Windows
choco install mkcert
```

```bash
mkcert -install   # installs the local mkcert CA into your OS/browser trust store (one-time)
mkdir -p certs
mkcert -cert-file certs/lim.ftfydemo.local.pem -key-file certs/lim.ftfydemo.local-key.pem lim.ftfydemo.local
mkcert -cert-file certs/ssc.ftfydemo.local.pem -key-file certs/ssc.ftfydemo.local-key.pem ssc.ftfydemo.local
```

Add entries to your `/etc/hosts` file (or equivalent) so the hostnames resolve to your Docker host, e.g.:

```
127.0.0.1 lim.ftfydemo.local ssc.ftfydemo.local
```

### 3. Start the stack

```bash
# Start everything in the "default" profile (traefik, lim, ssc, jenkins, jira, nexus, scancentral-sast, ...)
docker compose --env-file demo.env --profile default up -d

# Or start only specific profiles, e.g. traefik + lim + ssc
docker compose --env-file demo.env up -d traefik lim ssc
```

When you first sign in to SSC at `https://ssc.onfortify.com/`, use the demo account `admin` with password `admin`.
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

The controller is available at `https://scancentral-sast-controller.onfortify.com/scancentral-ctrl/`.
Its public hostname is configured by `SCANCENTRAL_SAST_CONTROLLER_HOSTNAME` in `demo.env`; the corresponding DNS A
record must point to the Docker host so Traefik can obtain a Let's Encrypt certificate.

The controller and sensor require token files and an internal TLS truststore in `scsast/secrets/`. These are runtime
secrets and are ignored by git.

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

- **Controller URL:** `https://scancentral-sast-controller.onfortify.com/scancentral-ctrl/`
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
curl -fsS -o /dev/null -w 'ScanCentral Controller HTTP %{http_code}\n' \
	https://scancentral-sast-controller.onfortify.com/scancentral-ctrl/
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

### 6. Stop / clean up

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
