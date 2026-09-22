# Fortify docker demo

This repository contains example docker compose files and scripts to setup a working Fortify ScanCentral SAST/DAST/SSC demo environment using the [fortifydocker](https://hub.docker.com/repositories/fortifydocker) images.
It also includes optional Sonatype Nexus Repository, IQ Server and Jenkins setup for integrations. 

## Prerequisites

### Docker

Install the latest version of docker for your target o/s, e.g. ubuntu.

### fortify.license file

A working **fortify.license** file for SSC and ScanCentral SAST.
Place this file in the "files" directory of the project.

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

### 4. Check status and logs

```bash
docker compose --env-file demo.env ps
docker compose --env-file demo.env logs -f lim
```

### 5. Stop / clean up

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
