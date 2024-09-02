# Fortify docker demo (Linux)

This repository contains some example docker compose files to setup a working Fortify ScanCentral SAST/DAST
demo environment using the [fortifydocker](https://hub.docker.com/repositories/fortifydocker) images on Linux.
It also includes Sonatype Nexus Repository, IQ Server and Jenkins for integrations. 

## Prerequisites

### Docker

Install the latest version of docker for your target o/s, e.g. ubuntu.

### fortify.license file

A working **fortify.license** file for SSC and ScanCentral SAST.
Place this file in the "root" directory of the project.

### Dockerhub ***fortifydocker*** credentials

You will need Docker Hub credentials to access the private docker images in the [fortifydocker](https://hub.docker.com/u/fortifydocker) organisation.

### ScanCentral DAST and WebInspect licenses

### Sonatype Nexus IQ Server license

## Environment preparation

Edit the `.env` file if you wish to use any different versions of the products and/or different ports

## Create Docker Network

If it does not already exist, create the docker network to be used with the following command:

```aidl
sudo docker network create ftfydemo_net
```

## Start  LIM

The License Infrastructure Manager (LIM) should be started separately to the rest of the containers.
To do this execute the following commands:

```aidl
cd lim
docker compose --env-file ../.env up -d
```

## Install License

Navigate to LIM URL and install the license(s) that you require.

## Start Containers

Start the containers using the following:

```aidl
docker compose up -d
```

When the `ssc` container has started run the following script to reset the admin users password.

```aidl
./reset-ssc-admin-user.sh
```

## Remove Containers

If you wish to remove the containers you can use the following command:

```aidl
docker compose down
```

Any data will be still remain in the volumes created, if you wish to remove the volumes then run the following command:

```aidl
docker volume rm fortify-docker-demo_ftfydata_jenkins fortify-docker-demo_ftfydata_scsast_ctrl fortify-docker-demo_ftfydata_scsast_sensor \
  fortify-docker-demo_ftfydata_sonatype-logs fortify-docker-demo_ftfydata_sonatype-work fortify-docker-demo_ftfydata_ssc
```  
