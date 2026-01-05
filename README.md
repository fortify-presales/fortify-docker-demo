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

## demo.ps1 details

`demo.ps1` is a PowerShell helper that wraps `docker compose` and adds convenience features for this demo:

- **Actions:** `start`, `stop`, `status`, `ps`, `logs`, `config`, `clean`, `help`.
- **`config` action:** shows the resolved compose configuration. The script passes `--profile default` to `docker compose config` when the compose CLI supports profiles, so services defined under the `default` profile are included. Use `-Profile` to override the profile used.
- **`--env-file` / `demo.env`:** when `demo.env` (or a custom `-ImageVersionsFile`) exists the script adds it as a global `--env-file` to all compose commands so image tag overrides and environment values are applied consistently.
- **Logs behavior:** `.\\demo.ps1 logs` returns the last 200 lines by default; use `-Follow` to stream logs.
- **LIM volume permissions:** `start` runs a best-effort permission fix (chown to the LIM runtime UID) on the LIM named volume to avoid runtime permission errors.
- **mkcert:** the script will attempt to generate TLS certs for `lim.ftfydemo.local` and `ssc.ftfydemo.local` using `mkcert` and will prompt for elevation if necessary.

## Windows shim (optional)

For convenience on Windows you can create a shim in a directory on your PATH (for example `C:\Users\<you>\bin`) named `demo.cmd` containing:

```bat
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<you>\repos\fortify-docker-demo\demo.ps1" %*
```

This lets you run `demo` from cmd.exe or PowerShell with the same arguments (e.g. `demo start`).

## Running the demo script

You can control the demo environment with the `demo.ps1` PowerShell script. Common actions:

- `start`: bring up the compose stack (creates volumes, networks, and containers). The script will also generate mkcert TLS certificates if needed and can apply an image tag override via `-LIMVersion`.
- `stop`: stop (or `down`) the compose stack. By default `stop` performs `docker compose down`.
- `status` / `ps`: show compose status or `docker ps` filtered to the project.
- `logs`: show service logs; use `-Service <name>` and `-Follow` to tail (stream) logs.
- `clean`: remove compose resources, named volumes, the demo network and the generated `certs/` directory.

Examples

```powershell
# Start the full demo (uses demo.env for image tags)
.\\demo.ps1 start

# Start and override LIM image version
.\\demo.ps1 start -LIMVersion 25.4.ubi.9

# Tail LIM logs interactively
.\\demo.ps1 logs -Service lim -Follow

# Stop and remove containers (compose down)
.\\demo.ps1 stop

# Clean everything: stop, remove volumes, network and generated certs
.\\demo.ps1 clean
```

Notes

- If you need to regenerate the mkcert certificates, pass `-RecreateCerts` to `start`.
- The `-ComposeDir` and `-ProjectName` parameters let you target alternate compose files or project names.
- The script includes an automatic permission-fix for the LIM named volume on `start` (chown/chmod) to avoid runtime permission errors when LIM writes its database and certificates.

---

Kevin A. Lee (kadraman) - klee2@opentext.com
