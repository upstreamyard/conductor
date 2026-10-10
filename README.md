# Conductor container image

Multi-arch (`amd64`, `arm64`), signed container images for [Conductor OSS](https://github.com/conductor-oss/conductor), the open-source workflow orchestration engine originally built at Netflix. Server and UI in one image.

> Community-maintained by **upstreamyard**. This is not an official Conductor image. Conductor is © its authors and licensed under Apache-2.0 (license text in `/licenses/conductor/LICENSE` inside the image).

| Registry | Image |
|---|---|
| Docker Hub | `upstreamyard/conductor` |
| GitHub Container Registry | `ghcr.io/upstreamyard/conductor` |

**Tags:** `latest`, `<major>.<minor>` (e.g. `3.32`), `<version>` (e.g. `3.32.5`, matching the [Conductor releases](https://github.com/conductor-oss/conductor/releases)). Only stable releases are built: release candidates (`-rc`) never get a tag here, and `latest` always points to the newest stable release. New releases are built automatically within 24 hours.

## At a glance

| | |
|---|---|
| Ports | `8080` API and Swagger UI (`/swagger-ui/index.html`), `5000` UI (nginx, proxies `/api` to the server) |
| Health | `GET /health` on `8080`. It reports the process only, not the database |
| Metrics | `GET /actuator/prometheus` on `8080` |
| Requires | nothing for a quick trial (built-in SQLite). For production: PostgreSQL (tested with `postgres:16`), or one of Conductor's other backends |
| Runs as | non-root UID `10001` |
| Migrations | automatic on startup |
| Default auth | none. Anyone who can reach ports 8080 or 5000 can create and run workflows |

**AI agents and coding assistants:** read [`AGENTS.md`](https://github.com/upstreamyard/conductor/blob/main/AGENTS.md) for deployment rules, and [`llms.txt`](https://github.com/upstreamyard/conductor/blob/main/llms.txt) for an index of all docs.

## Quick start

Try it without any dependencies (data is stored in SQLite inside the container and lost when it is removed):

```bash
docker run -d -p 8080:8080 -p 5000:5000 upstreamyard/conductor:latest
curl http://localhost:8080/health
```

Open the UI at http://localhost:5000 and the API docs at http://localhost:8080/swagger-ui/index.html.

With PostgreSQL, using our Compose file:

```bash
curl -O https://raw.githubusercontent.com/upstreamyard/conductor/main/docker-compose.yml
docker compose up -d
```

Your workers (your own code, in any language with a [Conductor SDK](https://github.com/conductor-oss/conductor)) connect to `http://<host>:8080/api`.

## Configuration

Conductor is a Spring Boot application, so every property can be set as an environment variable: upper-case, with `.` and `-` replaced by `_` (`conductor.db.type` becomes `CONDUCTOR_DB_TYPE`). PostgreSQL for persistence, queues and search:

```bash
docker run -d -p 8080:8080 -p 5000:5000 \
  -e CONDUCTOR_DB_TYPE=postgres \
  -e CONDUCTOR_QUEUE_TYPE=postgres \
  -e CONDUCTOR_INDEXING_ENABLED=true \
  -e CONDUCTOR_INDEXING_TYPE=postgres \
  -e CONDUCTOR_ELASTICSEARCH_VERSION=0 \
  -e CONDUCTOR_EXTERNAL_PAYLOAD_STORAGE_TYPE=postgres \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://your-postgres:5432/conductor \
  -e SPRING_DATASOURCE_USERNAME=conductor \
  -e SPRING_DATASOURCE_PASSWORD=... \
  upstreamyard/conductor:latest
```

### Config files (`CONFIG_PROP`)

As in the Conductor project's own image (`conductoross/conductor`), `CONFIG_PROP` selects a properties file in `/app/config`. Mount your own file there:

```bash
docker run -d -p 8080:8080 -p 5000:5000 \
  -v ./conductor.properties:/app/config/conductor.properties:ro \
  -e CONFIG_PROP=conductor.properties \
  upstreamyard/conductor:latest
```

The image also contains the Conductor project's example files (`config-postgres.properties`, `config-redis-os.properties`, …). They expect the host names from the Conductor project's Compose files (`postgresdb`, `rs`, `os`) and default passwords, so for real deployments use your own file or environment variables.

Two things to know (both tested):

- **The config file wins over environment variables.** This is how Conductor itself works: values from `CONFIG_PROP` are loaded as Java system properties, which take precedence. Don't set the same property in both places.
- **A missing file stops the container.** If `/app/config/$CONFIG_PROP` doesn't exist, the container exits with `ERROR: CONFIG_PROP=..., but /app/config/... does not exist`. The Conductor project's own image instead starts silently with the built-in SQLite defaults, which ignores your database.

### Other settings

| Variable | Default in image | Notes |
|---|---|---|
| `CONFIG_PROP` | – | Properties file name in `/app/config` |
| `JAVA_OPTS` | empty | JVM options, e.g. `-Xmx2g` or `-XX:MaxRAMPercentage=75` |
| `SERVER_PORT` | `8080` | The UI on `5000` proxies to `localhost:8080`, so keep the default if you use the UI |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, … | – | Optional keys for Conductor's LLM tasks. Without them the server logs `cannot init ... model` errors at startup. These are harmless |

All properties and their defaults: the Conductor project's [`application.properties`](https://github.com/conductor-oss/conductor/blob/main/server/src/main/resources/application.properties). Like the Conductor project's own image, the server is built with the Elasticsearch 7 client. OpenSearch and Elasticsearch 8 need a different build of the server and aren't included. Tested here: SQLite (default) and PostgreSQL for persistence, queues and indexing.

## Kubernetes

A Helm chart for this image is in preparation in [`upstreamyard/helm-charts`](https://github.com/upstreamyard/helm-charts). Until then, the facts you need for your own manifests:

- The container runs as non-root UID `10001` and works with `runAsNonRoot: true`.
- Use `GET /health` on port `8080` for liveness and readiness. It doesn't check the database.
- Run **one replica** for now. Conductor's default workflow lock is `local_only`, also in the Conductor project's PostgreSQL example config, so several replicas aren't safe without a distributed lock. Multi-replica setups will be tested and documented with the Helm chart.
- Pass passwords as environment variables from a Secret (`SPRING_DATASOURCE_PASSWORD`), not in a config file.

## Verifying images

Images are signed keylessly with [cosign](https://github.com/sigstore/cosign) and include an SBOM and SLSA provenance:

```bash
cosign verify upstreamyard/conductor:latest \
  --certificate-identity-regexp '^https://github.com/upstreamyard/conductor/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect upstreamyard/conductor:latest --format '{{ json .SBOM }}'
```

## How it's built

[`.github/workflows/build.yml`](https://github.com/upstreamyard/conductor/blob/main/.github/workflows/build.yml) checks out the Conductor release tag and builds [`Dockerfile`](https://github.com/upstreamyard/conductor/blob/main/Dockerfile) with the same Gradle command as the Conductor project's release workflow. Before publishing, [`scripts/smoke-test.sh`](https://github.com/upstreamyard/conductor/blob/main/scripts/smoke-test.sh) runs on native amd64 and arm64 runners. It starts the image against PostgreSQL, runs a workflow end to end, checks the UI and its `/api` proxy, and checks that a missing config file is rejected. Nothing is published unless both architectures pass. Everything is public and reproducible.

Same layout as the Conductor project's own image `conductoross/conductor` (`docker/server/Dockerfile`): server on `8080`, nginx with the UI on `5000`, `CONFIG_PROP`, files under `/app`. The differences:

- runs as non-root UID `10001` instead of root;
- `tini` as PID 1, and Java gets stop signals, so `docker stop` shuts down cleanly instead of being killed after the timeout;
- logs go to stdout only (the Conductor project's image also writes `/app/logs/server.log`);
- a `CONFIG_PROP` file that doesn't exist stops the container with an error, instead of falling back to SQLite;
- base images pinned by digest instead of `debian:stable-slim`;
- release candidates are never tagged. The Conductor project's `latest` sometimes points to an RC.

## Support

Issues with the image: [open an issue here](https://github.com/upstreamyard/conductor/issues). Issues with Conductor itself: [conductor-oss/conductor](https://github.com/conductor-oss/conductor/issues).
