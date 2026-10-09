# AGENTS.md

Instructions for AI agents and coding assistants working with this repository or deploying the image it publishes.

## Image facts

| Key | Value |
|---|---|
| Image | `upstreamyard/conductor` (Docker Hub), `ghcr.io/upstreamyard/conductor` |
| Tags | `<version>` (e.g. `3.32.5`), `<major>.<minor>` (e.g. `3.32`), `latest`. Stable releases only, never `-rc` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Ports | `8080` REST API (`/api`), Swagger UI (`/swagger-ui/index.html`); `5000` UI (nginx, proxies `/api` to `localhost:8080`) |
| Health | `GET /health` on 8080. Process only, does not check the database |
| Metrics | `GET /actuator/prometheus` on 8080 |
| User | non-root, UID/GID `10001` |
| Entrypoint | `tini --`, default command `/app/startup.sh` (starts nginx in the background, then execs Java) |
| Default storage | SQLite file `/app/libs/c123.db` inside the container (lost when the container is removed) |
| Production storage | PostgreSQL, tested with `postgres:16` |
| Config | Spring properties as env vars (`CONDUCTOR_DB_TYPE`, `SPRING_DATASOURCE_URL`, …) or a properties file in `/app/config` selected by `CONFIG_PROP` |
| Upstream | https://github.com/conductor-oss/conductor (Apache-2.0) |

## Deploying the image

Rules that avoid the common failures:

- **PostgreSQL:** set `CONDUCTOR_DB_TYPE=postgres`, `CONDUCTOR_QUEUE_TYPE=postgres`, `CONDUCTOR_INDEXING_ENABLED=true`, `CONDUCTOR_INDEXING_TYPE=postgres`, `CONDUCTOR_ELASTICSEARCH_VERSION=0`, `CONDUCTOR_EXTERNAL_PAYLOAD_STORAGE_TYPE=postgres`, and `SPRING_DATASOURCE_URL=jdbc:postgresql://HOST:5432/DB`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`. Tables are created on startup.
- **Config file vs env:** a file selected with `CONFIG_PROP` overrides environment variables for the same property. Use one or the other per property; keep passwords in env vars from a Secret.
- **Missing config file:** if `/app/config/$CONFIG_PROP` doesn't exist, the container exits with code 1 and `ERROR: CONFIG_PROP=... does not exist`. Fix the mount or the name. Upstream's image would silently start on SQLite instead.
- **Upstream example configs** in `/app/config` expect host names `postgresdb`, `rs`, `os` and default passwords. Don't use them for real deployments.
- **Replicas:** run one. The default workflow lock is `local_only`; several replicas need a distributed lock and are not yet tested here.
- **Auth:** there is none. Never expose ports 8080 or 5000 publicly without auth in front.
- **UI:** works only when the server listens on `8080` in the same container (`SERVER_PORT` unchanged).
- **LLM keys** (`OPENAI_API_KEY`, …) are optional; startup errors `cannot init ... model` without them are harmless.

Ready-to-use manifests:

- Docker Compose: [`docker-compose.yml`](docker-compose.yml) (Conductor and PostgreSQL)
- Kubernetes: Helm chart in preparation in https://github.com/upstreamyard/helm-charts

Verify a deployment:

```bash
curl -sf http://HOST:8080/health
curl -sf http://HOST:5000/ >/dev/null && echo "UI up"
```

## Working on this repository

Layout:

- `Dockerfile`: builds the upstream source, which CI checks out into `./upstream/` (git-ignored)
- `startup.sh`: based on upstream's `docker/server/bin/startup.sh`; also rejects a missing `CONFIG_PROP` file
- `nginx.conf`: nginx main config for running as non-root; the server block is upstream's `docker/server/nginx/nginx.conf`
- `scripts/smoke-test.sh`: smoke test used by CI and locally
- `.github/workflows/build.yml`: resolves the newest stable upstream release, smoke-tests on native amd64 and arm64 runners, then builds multi-arch, pushes, signs and syncs the Docker Hub README

Build and test locally:

```bash
git clone --depth 1 --branch v3.32.5 https://github.com/conductor-oss/conductor.git upstream
docker build -t conductor:dev --build-arg CONDUCTOR_VERSION=3.32.5 .
./scripts/smoke-test.sh conductor:dev
CONDUCTOR_IMAGE=conductor:dev docker compose up -d
```

Rules:

- Never push to `main`. Create a branch and open a pull request into `main`.
- Do not modify upstream source. Fix packaging problems in the `Dockerfile` and report upstream bugs at https://github.com/conductor-oss/conductor/issues.
- Stay close to upstream's image layout (ports, `/app` paths, `CONFIG_PROP`); document every difference in the README.
- Keep the image non-root with UID `10001`, and keep `HEALTHCHECK` and the OCI labels.
- When ports, endpoints or required settings change upstream, update `README.md`, this file, `llms.txt`, `docker-compose.yml` and the smoke test in the same pull request.
- The workflow must pass `actionlint` (`docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest`).
- `README.md` is also the Docker Hub description, so keep it under 25,000 characters.
