# Xtracta Database Migration Assessment

This project completes the `schema-data-migration` (`sdm`) step-by-step exercise from database preparation through rollback. It uses two isolated MySQL containers: production provides the initial schema, while all migrations and rollbacks are tested against dev.

## Environment

| Component | Version / configuration |
|---|---|
| Host OS | macOS 26.6 (`arm64`, Apple Silicon) |
| Docker Desktop | 4.91.0 |
| Docker CLI | 29.8.0 |
| Docker Compose | 5.5.1 |
| MySQL | 8.0.46 |
| `sdm` | 0.6.4 |
| Skeema | 1.12.3-community |
| Production | `host.docker.internal:3306/awesome_db` |
| Dev | `host.docker.internal:3307/awesome_db` |

The guide's initial SQL uses `int(11)`. MySQL 8.0 accepts that definition but normalizes it to `int` when the schema is read back; the integer storage type is unchanged.

The upstream `sdm` image is pinned in `Dockerfile.sdm` by digest:

```text
sha256:13ac9b079b48ec9e3aa090780f0e6517011a8ada201141059b8e4916db237bc8
```

## How `sdm` works

In my own words, `sdm` combines a desired-state schema model with ordered migration plans. SQL files under `schema/` describe what the schema should look like. For a schema migration, `sdm` stores immutable before-and-after schema snapshots in `.schema_store/`; Skeema compares those snapshots with the live database and generates the required DDL.

Each migration plan is a JSON file with a version, name, type, changes, and dependencies. Dependencies determine execution order rather than relying only on filenames. Data migrations contain explicit forward and backward operations, such as an `INSERT` paired with a `DELETE`.

When a migration runs, `_migration_history` records the migrations currently applied to that environment. `_migration_history_log` keeps the longer audit trail, including successful applications and rollbacks. A dry run displays pending work without changing the database.

The local flow is:

```text
production MySQL :3306 ──sdm init──> schema model + 0000_init
                                           |
                                           v
                                   versioned migration plans
                                           |
                                           v
                                  dev MySQL :3307
                                  migrate / rollback
```

## Project structure

```text
awesome_project/
├── .schema_store/                 # Immutable schema snapshots used by plans
├── data/                          # Reserved for file-based data migrations
├── hooks/pre-commit               # Docker-aware sdm validation hook
├── migration_plan/
│   ├── 0000_init.json
│   ├── 0001_add_address_to_user_tab.json
│   └── 0002_seed_user_table.json
├── schema/
│   ├── .skeema                    # Production and dev connection definitions
│   └── user.sql                   # Desired user-table schema
├── scripts/export_history.py      # Reproducible CSV exporter
├── setup/                         # Initial production and dev SQL
├── _migration_history.csv
├── _migration_history_log.csv
├── compose.yaml
├── db.sh                          # Docker Compose helper
├── Dockerfile.sdm                 # Apple Silicon compatibility image
└── sdm.sh                         # sdm Docker helper
```

## Local configuration

Docker Desktop must be installed and running. Create the two ignored local environment files before running commands from a fresh clone:

```bash
cp .docker.env.example .docker.env
cp .env.example .env
```

Set the same disposable local password in `MYSQL_ROOT_PASSWORD` and `MYSQL_PWD` in `.docker.env`, and set `MYSQL_PWD` to that value in `.env`. The real `.docker.env` and `.env` files are intentionally excluded from Git.

Start and inspect the database containers:

```bash
./db.sh up -d
./db.sh ps
```

`db.sh` and `sdm.sh` automatically find the Docker CLI inside Docker Desktop, even when it is not installed on the shell `PATH`.

## Commands executed

These commands document the completed assessment in the required order. The generation commands should not be rerun against this already-initialized repository because their output is committed.

### 1. Prepare databases

The production setup creates `awesome_db.user`; the dev setup creates an empty `awesome_db`:

```bash
./db.sh exec -T production-db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' < setup/production.sql

./db.sh exec -T dev-db sh -c \
  'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' < setup/dev.sql
```

### 2. Initialize project

Because `sdm` runs inside Docker, `host.docker.internal` represents the Mac host. Host ports `3306` and `3307` correspond to the ports in the assessment guide.

```bash
./sdm.sh init \
  --host host.docker.internal \
  --port 3306 \
  -u root \
  --schema awesome_db
```

This generated `0000_init.json`, `schema/user.sql`, `schema/.skeema`, `.schema_store/`, `.env`, and the supporting TypeScript files.

### 3. Add dev environment

```bash
./sdm.sh add-env \
  --host host.docker.internal \
  --port 3307 \
  -u root \
  dev
```

This added the `[dev]` section to `schema/.skeema` without changing the dev database.

### 4. Apply initial migration

```bash
./sdm.sh migrate dev --dry-run
./sdm.sh migrate dev
```

Migration `0000_init` created the `user` table in dev and initialized the two migration-history tables.

### 5. Create and apply schema migration

I added this column to `schema/user.sql`:

```sql
`address` varchar(255) CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci NOT NULL
```

Then I generated, previewed, and applied the plan:

```bash
./sdm.sh make-schema add_address_to_user_tab
./sdm.sh migrate dev --dry-run
./sdm.sh migrate dev
```

The resulting `0001_add_address_to_user_tab.json` depends on `0000_init` and contains both forward and backward schema snapshot IDs. Skeema applied:

```sql
ALTER TABLE `user`
  ADD COLUMN `address` varchar(255)
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci NOT NULL;
```

### 6. Show migration history

```bash
./sdm.sh info dev
```

At this point, `0000_init` and `0001_add_address_to_user_tab` were both `SUCCESSFUL`.

### 7. Create and apply data migration

```bash
./sdm.sh make-data seed_user_table sql
```

I replaced the generated placeholder SQL in `0002_seed_user_table.json` with a forward insert and a targeted backward delete:

```sql
-- Forward
INSERT INTO `user` (`id`, `name`, `address`)
VALUES (1, 'foo', 'bar');

-- Backward
DELETE FROM `user` WHERE `id`=1;
```

I then previewed and applied it:

```bash
./sdm.sh migrate dev --dry-run
./sdm.sh migrate dev
./sdm.sh info dev
```

The inserted row was verified as `(1, 'foo', 'bar')`, and all three migrations were `SUCCESSFUL`.

### 8. Roll back to `0000`

```bash
./sdm.sh rollback --version 0000 dev --dry-run
./sdm.sh rollback --version 0000 dev
./sdm.sh info dev
./sdm.sh diff 0 dev -v
```

The rollback ran in reverse dependency order:

1. `0002` deleted user ID `1`.
2. `0001` dropped the `address` column.

The final `sdm diff` returned successfully with no schema difference between dev and version `0000`.

### 9. Export migration history

```bash
./scripts/export_history.py
```

The exporter uses Python's CSV library so that the JSON `snapshot` values in `_migration_history_log` are quoted correctly.

## Verification results

| Check | Result |
|---|---|
| Final dev `user` columns | `id`, `name` |
| Final dev user row count | `0` |
| Final current history | Only `0000_init`, state `SUCCESSFUL` |
| Audit-log rows | `10` |
| `_migration_history.csv` rows | 1 header + 1 data row |
| `_migration_history_log.csv` rows | 1 header + 10 data rows |
| `sdm check integrity` | Passed |
| `sdm diff 0 dev -v` | No differences |
| Production after dev tests | Unchanged |

The audit log contains this operation sequence:

```text
create, update_succ,
create, update_succ,
create, update_succ,
update_rollback, delete,
update_rollback, delete
```

## Challenge and solution

The main challenge was running the upstream `sdm` Docker image on an Apple Silicon Mac. The image contains an AMD64 build of Skeema. Basic `sdm` commands worked under emulation, but Skeema crashed with a segmentation fault when it opened a network connection to MySQL. Adding an explicit Docker host mapping did not resolve the crash, which showed that the issue was the emulated executable rather than the database credentials or schema.

I kept the official `sdm 0.6.4` image and replaced only its Skeema executable with the official ARM64 Skeema 1.12.3 binary. `Dockerfile.sdm` pins the upstream `sdm` image by digest and verifies Skeema's published SHA-256 checksum before installing it. `sdm.sh` detects Apple Silicon and builds this compatibility image automatically. After that change, `sdm init`, schema migrations, data migrations, history inspection, and rollback all completed successfully.

Docker may still display a platform warning because the Python portion of the upstream `sdm` image remains AMD64. This is expected; the network-sensitive Skeema process runs natively as ARM64.

## Useful validation commands

```bash
./sdm.sh check integrity
./sdm.sh clean store --dry-run --skip-integrity
./sdm.sh info dev
./sdm.sh diff 0 dev -v
```

The same integrity and schema-store checks run through `hooks/pre-commit` before each Git commit.

To stop the databases while preserving their named volumes:

```bash
./db.sh down
```

Running `./db.sh down -v` also deletes the database volumes and should only be used when intentionally rebuilding the assessment from the setup SQL.

## References

- [`schema-data-migration` repository](https://github.com/Beim/schema-data-migration)
- [Official step-by-step guide](https://github.com/Beim/schema-data-migration/blob/main/docs/step_by_step_guide.md)
- [Skeema documentation](https://www.skeema.io/docs/)
