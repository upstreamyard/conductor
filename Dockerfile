# Container image for Conductor OSS (https://github.com/conductor-oss/conductor)
# Maintained by upstreamyard. Builds the Conductor source code, checked out into ./upstream
# at the release tag selected by CI.
#
# Same layout as the Conductor project's own image (docker/server/Dockerfile): Conductor server on 8080,
# UI served by nginx on 5000 (proxying /api to the server), config via CONFIG_PROP.
# Packaging changes: non-root user, tini as PID 1, pinned base images.

# -----------------------------
# Server jar (architecture-independent, built on the build host)
# -----------------------------
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk-noble@sha256:b468c3fc688b14450571494f588bd939378e7fd542ed5a73f8efc13f17872a87 AS builder

ARG CONDUCTOR_VERSION=0.0.0
# Indexing backend compiled into the jar; the Conductor project's default is elasticsearch (Elasticsearch 7).
ARG INDEXING_BACKEND=elasticsearch

WORKDIR /conductor
COPY upstream/ ./

# Same Gradle invocation as the Conductor project's release workflow (publish.yml).
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew :conductor-server:build -x test -x spotlessCheck -x shadowJar \
      -x :conductor-os-persistence-v3:build \
      -Pversion=${CONDUCTOR_VERSION} \
      -PindexingBackend=${INDEXING_BACKEND} \
      -Dorg.gradle.jvmargs=-Xmx2g \
      --no-daemon --no-parallel

# -----------------------------
# UI (architecture-independent, built on the build host)
# -----------------------------
FROM --platform=$BUILDPLATFORM node:24-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS ui-builder

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

COPY upstream/ui-next /conductor/ui-next
WORKDIR /conductor/ui-next

RUN corepack enable && \
    pnpm install --frozen-lockfile && \
    NODE_OPTIONS=--max-old-space-size=4096 pnpm build

# -----------------------------
# Runtime
# -----------------------------
FROM eclipse-temurin:21-jre-noble@sha256:000fd431958bc81a24abe1e8e5f0f0fd3ae365a594bd50aadb20696805f9408c

ARG CONDUCTOR_VERSION=unknown

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx curl tini \
    && rm -f /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 conductor \
    && useradd --system --uid 10001 --gid 10001 --home-dir /app --no-create-home conductor \
    && mkdir -p /app/config /app/logs /app/libs \
    # The default SQLite database (c123.db) is written to /app/libs, as in the Conductor project's own image.
    && chown 10001:10001 /app/libs /app/logs

COPY --chmod=0755 startup.sh /app/startup.sh
COPY upstream/docker/server/config /app/config
COPY --from=builder /conductor/server/build/libs/*boot*.jar /app/libs/conductor-server.jar
COPY upstream/LICENSE /licenses/conductor/LICENSE

WORKDIR /usr/share/nginx/html
RUN rm -rf ./*
COPY --from=ui-builder /conductor/ui-next/dist .
COPY upstream/docker/server/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

ENV JAVA_OPTS=""

LABEL org.opencontainers.image.title="conductor" \
      org.opencontainers.image.description="Conductor OSS workflow orchestration server and UI. Community image by upstreamyard." \
      org.opencontainers.image.version="${CONDUCTOR_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="upstreamyard" \
      org.opencontainers.image.url="https://github.com/upstreamyard/conductor" \
      org.opencontainers.image.documentation="https://github.com/upstreamyard/conductor#readme"

EXPOSE 8080 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -sf -o /dev/null http://localhost:8080/health || exit 1

USER 10001:10001
WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/startup.sh"]
