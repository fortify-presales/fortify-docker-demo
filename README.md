# Fortify docker demo (Linux)

This repository contains some example scripts to setup a working Fortify ScanCentral SAST/DAST
demo environment using the [fortifydocker](https://hub.docker.com/repositories/fortifydocker) images on Linux. 

## Prerequisites

### Docker

Install **Hyper-V**: https://minikube.sigs.k8s.io/docs/drivers/hyperv/

### Docker Compose

Install **minikube**: https://minikube.sigs.k8s.io/docs/start/

### fortify.license file

A working **fortify.license** file for SSC and ScanCentral SAST.
Place this file in the "root" directory of the project.

### Dockerhub ***fortifydocker*** credentials

You will need Docker Hub credentials to access the private docker images in the [fortifydocker](https://hub.docker.com/u/fortifydocker) organisation.

### License and Infrastructure Manager and ScanCentral DAST and WebInspect licenses

ScanCentral DAST requires a working LIM instance with a license pool for WebInspect scanners. Unfortunately, LIM does not currently support Linux, so you cannot install it as part of this deployment.
Follow standard procedures to install and configure LIM on a Windows machine or using Windows containers. **LIM must be accessed in API mode. Using the URL for LIM service will not work.**


## Environment preparation

Create a `.env` file with settings that you wish to you, an example file is given below:

```aidl
# Default version of SSC, ScanCentral SAST etc to use
FORTIFY_VERSION=23.1
# LIM configuration
LIM_API_URL=http://_YOUR_LIM_SERVER_/LIM.API
LIM_ADMIN_USER=admin
LIM_ADMIN_PASSWORD=_YOUR_LIM_ADMIN_PASSWORD_
LIM_POOL_NAME=Default
LIM_POOL_PASSWORD=_YOUR_LIM_POOL_PASSWORD_
```
Note: Do not place this file in source control.

## Install environment

Run the following command to startup a new environment:

```aidl
.\startup.sh
```

It will take a while for everything to complete.

Once the details of the environment are complete at the end you will need to login to Fortify
SSC and enter the details of ScanCentral SAST/DAST as per the instructions.

If you want to populate the Fortify environment with some additional sample data, you can the following command:

```aidl
.\populate.sh
```

Note: if you need to reset the Fortify SSC "admin" user's password you can use the following script:

```aidl
.\scripts\reset-ssc-admin-user.ps1
```

## Remove environment

If you wish to remove the minikube environment completely, you can use the following command:

```aidl
.\shutdown.sh
```
