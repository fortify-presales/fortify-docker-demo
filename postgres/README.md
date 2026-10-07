# Shared PostgreSQL

Create the administrator password before initializing a service that uses this cluster:

```bash
mkdir -p postgres/secrets
openssl rand -base64 36 | tr -d '\n' > postgres/secrets/postgres-admin-password
chmod 600 postgres/secrets/postgres-admin-password
```

The administrator credential is used only for cluster administration and product database initialization. Each product must use a separate database and runtime role.

Sonatype Lifecycle uses the `iqserver` database owned by the unprivileged `iq` role. `nexus/start.sh` creates it through
an idempotent initializer, using `nexus/secrets/database-password` for IQ. Existing databases are not dropped, existing
role passwords are not overwritten, and conflicting ownership or elevated role permissions cause initialization to
fail. Preserve both the PostgreSQL volume and its existing secret files when restarting or restoring this demo.