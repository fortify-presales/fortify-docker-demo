#!/bin/bash
# docker pull fortifydocker/scancentral-dast-config:24.2.ubi.8
#
if [[ -z "${POSTGRES_DBO_PASSWORD}" ]]; then
	echo "Environment variable POSTGRES_DBO_PASSWORD has not been set"
	exit 1
fi
if [[ -z "${POSTGRES_DAST_PASSWORD}" ]]; then
	echo "Environment variable POSTGRES_DAST_PASSWORD has not been set"
	exit 1
fi
if [[ -z "${LIM_SERVICE_PASSWORD}" ]]; then
	echo "Environment variable LIM_SERVICE_PASSWORD has not been set"
	exit 1
fi
if [[ -z "${LIM_POOL_PASSWORD}" ]]; then
	echo "Environment variable LIM_POOL_PASSWORD has not been set"
	exit 1
fi

CURDIR=$(pwd)
docker run --rm -v $CURDIR:/app/logs -e "POSTGRES_DBO_PASSWORD=$POSTGRES_DBO_PASSWORD" -e "POSTGRES_DAST_PASSWORD=$POSTGRES_DAST_PASSWORD" -e "LIM_SERVICE_PASSWORD=$LIM_SERVICE_PASSWORD" -e "LIM_POOL_PASSWORD=$LIM_POOL_PASSWORD" --network ftfydemo_net fortifydocker/scancentral-dast-config:24.2.ubi.8 configureenvironment --mode autodeploy --settingsFile /app/logs/SampleSettingsFile.yaml --outputDirectory /app/logs
