# Shared PostgreSQL

Create the administrator password before initializing a service that uses this cluster:

```bash
mkdir -p postgres/secrets
openssl rand -base64 36 | tr -d '\n' > postgres/secrets/postgres-admin-password
chmod 600 postgres/secrets/postgres-admin-password
```

The administrator credential is used only for cluster administration and product database initialization. Each product must use a separate database and runtime role.