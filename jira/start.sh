#/bin/bash
docker compose --env-file ../.env up -d
sleep 5
docker cp mysql-connector-j-8.0.33.jar jira:/opt/atlassian/jira/lib
docker compose restart jira
docker compose logs --follow

