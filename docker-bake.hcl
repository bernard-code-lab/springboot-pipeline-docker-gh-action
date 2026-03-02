# Empty target required for docker/metadata-action bake-file integration.
# The metadata-action injects tags and labels into this target; our build target inherits from it.
target "docker-metadata-action" {}

variable "REGISTRY" {
  default = "docker.io/rafaelc869"
}

variable "TAG" {
  default = "latest"
}

variable "ENVIRONMENT" {
  default = "development"
}

group "default" {
  targets = ["springboot-pipeline-docker-gh-action"]
}

# Tags and labels come from metadata-action bake-file (sha-*, branch, semver, OCI labels).
# We only define build-specific settings here.
target "springboot-pipeline-docker-gh-action" {
  inherits  = ["docker-metadata-action"]
  context   = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64", "linux/arm64"]
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
  args = {
    ENVIRONMENT = "${ENVIRONMENT}"
  }
}
