# ScanCentral DAST runtime files

Create these one-line files under `scdast/secrets/` with mode `600` before running `./scdast/manage.sh init`:

- `database-password`: password for the DAST-only PostgreSQL runtime role.
- `service-token`: at least 10 characters; shared by the DAST API and scanner service.
- `core-datastore-password`: password for the Utility Service scanner datastore.
- `scanner-datastore-password`: password for the fixed scanner datastore.
- `twofa-master-token`: token shared by the scanner and 2FA service.
- `fortifyconnect-private-key`: base64-encoded private key contents.
- `fortifyconnect-public-key`: base64-encoded public key contents.

The PostgreSQL administrator password is stored separately at `postgres/secrets/postgres-admin-password`. Generated runtime configuration is written to `scdast/generated/`; both directories are ignored by git.

The demo integration credentials are configured in `demo.env`: `SSC_DAST_USERNAME`, `SSC_DAST_PASSWORD`, `LIM_USERNAME`, `LIM_PASSWORD`, `LIM_POOL_NAME`, and `LIM_POOL_PASSWORD`. Do not use tracked environment files for production credentials.

The management commands are:

```bash
./scdast/manage.sh init
./scdast/manage.sh validate
./scdast/manage.sh up
./scdast/manage.sh down
./scdast/manage.sh manage
./scdast/manage.sh upgrade --backup-complete
./scdast/manage.sh reset --confirm
```

`reset` removes only the DAST database, role, and generated runtime files. It does not remove the shared PostgreSQL volume or databases owned by other products.