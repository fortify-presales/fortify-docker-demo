#/bin/bash
docker compose build --env-file ../.env
docker compose --env-file ../.env up -d
