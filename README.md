# Spring Boot + Docker + GitHub Actions Pipeline

Reference implementation for the article: a production-style CI/CD pipeline for a Spring Boot API using Docker’s official GitHub Actions — multi-stage image, Docker Bake, branch-based deploy, CVE scanning, and attestation.

## What’s in this repo

- **Multi-stage Dockerfile** — JDK build stage with Maven cache and dependency layer; JRE runtime stage with non-root user, `HEALTHCHECK`, and optional `ENVIRONMENT`.
- **Docker Bake** (`docker-bake.hcl`) — Declarative multi-platform build (amd64 + arm64), GHA cache; tags (e.g. `sha-*`, branch, semver) and OCI labels come from `docker/metadata-action` via `inherits`; same command locally and in CI.
- **Two pipelines:**
  - **CI** (on every PR): unit tests → Docker build checks (lint). Tests run first so failed tests don’t trigger Docker setup.
  - **Deploy** (on push to `development` / `staging` / `production`): unit tests → build image → integration smoke test with Compose → Docker Scout CVE scan → Bake build & push → attestation → (on `production`) Docker Hub description update.
- **Reusable workflow** — `test.yml` is used by both CI and Deploy so test steps stay in one place.

## Project structure

```
springboot-pipeline-docker-gh-action/
├── src/main/java/.../
├── Dockerfile
├── docker-bake.hcl
├── docker-compose.yml          # used by CI for integration test (app: springboot-pipeline-docker-gh-action:test)
├── compose.yaml                # optional local override
├── pom.xml
├── mvnw, .mvn/
└── .github/workflows/
    ├── ci.yml                  # PR: test + Docker lint
    ├── deploy.yml              # push to dev/staging/prod: test, build, scan, push, attest
    └── test.yml                # reusable: Maven unit tests
```

## Quick start

**Run the app locally (no Docker):**

```bash
./mvnw spring-boot:run
```

**Build the image locally (single platform):**

```bash
docker build -t springboot-pipeline-docker-gh-action:local .
```

**Build with Bake (multi-platform, same as CI):**

```bash
ENVIRONMENT=staging TAG=1.0.0 docker buildx bake
```

**Run with Compose (expects image `springboot-pipeline-docker-gh-action:test`):**

```bash
docker build -t springboot-pipeline-docker-gh-action:test .
docker compose -f docker-compose.yml up -d
curl -s http://localhost:8080/actuator/health
docker compose down
```

## Dockerfile highlights

| Feature | Purpose |
|--------|---------|
| `dependency:go-offline` + separate `COPY pom.xml` | Cache Maven deps; only code changes trigger recompile. |
| `--mount=type=cache,target=/root/.m2` | Persist Maven cache across builds (huge time save after first run). |
| Non-root user `appuser` | Security baseline; Docker Scout reports if missing. |
| `HEALTHCHECK` with `curl` | Runtime health for orchestrators; Alpine JRE needs `curl` added. |
| `ENVIRONMENT` build arg | Optional env label/tag (e.g. development/staging/production). |

## What runs where

| Branch        | Unit tests | Scout scan | Platforms   | Registry   | Attestation | Docker Hub readme |
|---------------|------------|------------|-------------|------------|-------------|-------------------|
| development   | ✅         | ✅         | amd64+arm64 | GHCR       | ✅          | —                 |
| staging       | ✅         | ✅         | amd64+arm64 | Docker Hub | ✅          | —                 |
| production    | ✅         | ✅ (blocks on critical/high CVE) | amd64+arm64 | Docker Hub | ✅          | ✅ (README.md)    |

Environment and registry are derived from the branch in `deploy.yml` (e.g. development → `ghcr.io/myorg/...`, staging/production → `docker.io/myorg/...`).

## Deploy and rollback

- **Use digest or immutable tags.** For idempotent deploy and safe rollback, reference the image by **digest** (e.g. `docker.io/myorg/springboot-pipeline-docker-gh-action@sha256:...`) or by **immutable tag** (e.g. `sha-abc1234`). Do not rely only on mutable tags like `staging`, `production`, or `latest` — they change on every push.
- **Where to get the reference:** After each run, the Deploy workflow writes the image digest and `sha-*` tag to the job summary and exposes them as job outputs (`image_digest`, `image_sha_tag`) for use by downstream deploy jobs or runbooks. In a calling workflow, use `needs.build-and-push.outputs.image_digest` and `needs.build-and-push.outputs.image_sha_tag`.
- **Semver in production:** Tags like `1.2.3` or `latest` (for semver) are generated when the workflow runs on a **git tag** (e.g. `v1.2.3`). Pushing only to the `production` branch does not create semver tags; use `git tag v1.2.3 && git push origin v1.2.3` or trigger the workflow from a tag push if you want versioned tags.
- **Attestation:** Provenance and SBOM are attested for the primary image `docker.io/myorg/springboot-pipeline-docker-gh-action`. When the same image is pushed to GHCR, attestation is for the Docker Hub reference; both registries hold the same content.

## Required secrets (for Deploy workflow)

- **Docker Hub:** `DOCKER_USER` (variable) and `DOCKER_PAT` (secret) — used for push and (on `master`) for syncing the repo README to the Docker Hub full description. **Note:** Docker Hub Personal Access Tokens only allow registry (push/pull); the API to update repository description returns 403. The “Update Docker Hub description” step is best-effort (`continue-on-error`); the pipeline still succeeds if it fails. To actually update the description, use account password (with 2FA disabled) instead of PAT, or wait for Docker to add PAT scopes for repo metadata.
- **GHCR:** `GITHUB_TOKEN` — used automatically; no extra secret.

Optional: `MAVEN_TOKEN` if you need private Maven repos in the build.

## Tech stack

- Java 21, Spring Boot 4.x
- Eclipse Temurin Alpine (JDK for build, JRE for runtime)
- Docker Buildx, Bake, Compose
- GitHub Actions: `docker/setup-docker-action`, `docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/setup-compose-action`, `docker/login-action`, `docker/metadata-action`, `docker/build-push-action`, `docker/bake-action`, `docker/scout-action`, `actions/attest-build-provenance`, `peter-evans/dockerhub-description`

## License

MIT.

---

*This repo is the companion code for the article. For the full narrative, branch strategy, and “why each action” breakdown, see the article.*
