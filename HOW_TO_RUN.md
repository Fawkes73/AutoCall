# How to Run AutoCall

This repository currently contains the production architecture, database schema, Docker Compose wiring, Nginx/Prometheus configuration, backup script, and CI validation assets for the AI Travel Agency Voice Receptionist platform.

> Important: the FastAPI backend and React frontend source trees are described in the architecture document but are not yet checked into this repository. The provided `docker-compose.yml` expects deployable images named `autocall/backend` and `autocall/frontend`. Build and publish those images, or update the image names in `docker-compose.yml`, before starting the full runtime stack.

## 1. Prerequisites

Install these tools on the machine where you want to run or validate the project:

- Git.
- Docker Engine and Docker Compose v2.
- Bash.
- PostgreSQL client tools if you want to run the backup script directly on the host.
- Access credentials for production integrations when running a real deployment:
  - OpenAI API key.
  - Exotel credentials and webhook secret.
  - Zoho CRM OAuth credentials.
  - JWT signing secret.
  - PostgreSQL and Redis passwords.

## 2. Clone the Repository

```bash
git clone <repository-url> AutoCall
cd AutoCall
```

## 3. Review the Production Design

Start with the enterprise design document:

```bash
less docs/ai-travel-receptionist-production-design.md
```

The document explains the target architecture, service responsibilities, API contracts, RAG design, security controls, deployment sequence, monitoring, testing strategy, and cost assumptions.

## 4. Create the Environment File

Create a `.env` file in the repository root.

```bash
cat > .env <<'EOF_ENV'
APP_VERSION=latest
POSTGRES_DB=autocall
POSTGRES_USER=autocall
POSTGRES_PASSWORD=change-me-postgres-password
REDIS_PASSWORD=change-me-redis-password
GRAFANA_ADMIN_PASSWORD=change-me-grafana-password

# Replace these before any real integration test or production deployment.
OPENAI_API_KEY=replace-me
EXOTEL_ACCOUNT_SID=replace-me
EXOTEL_API_KEY=replace-me
EXOTEL_API_TOKEN=replace-me
EXOTEL_WEBHOOK_SECRET=replace-me
ZOHO_CLIENT_ID=replace-me
ZOHO_CLIENT_SECRET=replace-me
ZOHO_REFRESH_TOKEN=replace-me
JWT_SECRET_KEY=replace-me-with-strong-random-secret
EOF_ENV
```

For production, do not commit `.env`. Store secrets in a secure vault or inject them through your deployment platform.

## 5. Prepare Runtime Images

The Compose file references these images:

- `autocall/backend:${APP_VERSION:-latest}`
- `autocall/frontend:${APP_VERSION:-latest}`

Before running the full stack, do one of the following:

### Option A: Use published images

Push backend and frontend images to a registry, then update `docker-compose.yml` image names if needed.

```bash
export APP_VERSION=<image-tag>
docker compose pull
```

### Option B: Build local images

After backend and frontend source trees are added, build images locally with the same names expected by Compose:

```bash
docker build -t autocall/backend:latest ./backend
docker build -t autocall/frontend:latest ./frontend
```

## 6. Validate Configuration

Run these checks before starting services:

```bash
docker compose config
bash -n scripts/backup_postgres.sh
```

If Ruby is available, you can also parse the YAML files without Docker:

```bash
ruby -e 'require "yaml"; %w[docker-compose.yml deploy/prometheus.yml .github/workflows/ci.yml].each { |f| YAML.load_file(f); puts "#{f} yaml-ok" }'
```

## 7. Start the Stack

After runtime images and `.env` are ready, start the stack:

```bash
docker compose up -d
```

Check service status:

```bash
docker compose ps
docker compose logs -f api
```

Expected local endpoints:

- API: `http://localhost:8000`
- Frontend container: `http://localhost:3000`
- Nginx reverse proxy: `http://localhost`
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3001`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`

## 8. Initialize or Validate the Database Schema

The PostgreSQL container automatically loads `database/schema.sql` on first initialization through this mounted file:

```text
./database/schema.sql:/docker-entrypoint-initdb.d/001-schema.sql:ro
```

If the database volume already exists, initialization scripts will not run again. To recreate a local development database from scratch:

```bash
docker compose down -v
docker compose up -d postgres
```

To manually apply the schema to an existing database:

```bash
PGPASSWORD="$POSTGRES_PASSWORD" psql \
  --host localhost \
  --port 5432 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --file database/schema.sql
```

## 9. Run Backups

Run the PostgreSQL backup script from a host with `pg_dump` installed:

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=autocall
export POSTGRES_USER=autocall
export POSTGRES_PASSWORD=<your-postgres-password>
export BACKUP_DIR=/var/backups/autocall/postgres
export RETENTION_DAYS=14
./scripts/backup_postgres.sh
```

The script writes compressed `.sql.gz` backups and removes old backups beyond the configured retention window.

## 10. Stop the Stack

Stop containers while keeping local volumes:

```bash
docker compose down
```

Stop containers and remove local volumes, including PostgreSQL and Redis data:

```bash
docker compose down -v
```

## 11. Troubleshooting

### Docker is not installed

Install Docker Engine and Docker Compose v2, then rerun:

```bash
docker compose config
```

### Backend or frontend image is missing

If Compose reports that `autocall/backend` or `autocall/frontend` cannot be found, build or publish those images first, or update `docker-compose.yml` to point to your registry.

### PostgreSQL schema did not load

The schema only auto-loads when PostgreSQL initializes a new empty data directory. Remove the local volume for a clean development reset:

```bash
docker compose down -v
docker compose up -d postgres
```

### Redis requires a password

The Redis service is configured with `--requirepass`. Ensure `REDIS_PASSWORD` is set in `.env` before starting the stack.

### Grafana login fails

Grafana uses `GRAFANA_ADMIN_PASSWORD` from `.env` for the initial admin password. If the Grafana volume already exists, changing `.env` may not reset the stored admin password; reset it through Grafana tooling or recreate the local volume.

## 12. Production Notes

For real production deployment:

- Replace placeholder secrets with strong generated values.
- Enable HTTPS with real certificates in Nginx or at the load balancer.
- Use managed or hardened PostgreSQL and Redis for growth deployments.
- Store call recordings and backups in encrypted object storage.
- Configure Exotel webhooks to point to the public `/api/v1/telephony/exotel/*` endpoints.
- Configure OpenAI and Zoho budget/usage alerts.
- Run staging voice-call tests in English, Hindi, and Marathi before production cutover.
