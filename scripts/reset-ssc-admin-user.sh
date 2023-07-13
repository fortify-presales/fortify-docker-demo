#/bin/bash
echo "Resetting SSC admin user's password to 'admin'"
docker exec -it fortify-docker-demo_sscdemo_1 "mysql" -e "use sscdbdemo; UPDATE fortifyuser SET requirePasswordChange = 'N', failedLoginAttempts = 0, dateFrozen = NULL, suspended = 'N', password = '{sha}{P7D4co4mI/4=}b0521d842e68c870af598b81aa8cd6d1728611b1e5568397e420b2d026172b74' WHERE userName = 'admin';"