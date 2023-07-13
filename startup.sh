#!/bin/bash

if [[ ! -f "./.env" ]] ; then
    echo "Error: Could not find .env file, please see README.md for instructions."
    exit
fi

if [[ ! -f "./fortify.license" ]] ; then
    echo "Error: Could not find fortify.license file, please see README.md for instructions."
    exit
fi

source .env

docker-compose up -d

./scripts/reset-ssc-admin-user.sh

#JavaHome="$(pwd)/${JAVA_DIR}"
