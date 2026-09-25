# syntax=docker/dockerfile:1
# devbox go — Go toolchain layer. Toolchain only: this file names no agent and
# no harness (D2, criterion 7); the harness slot is filled by images/base.
#
# The base layer arrives as the named build context `base` (see images/lisp for
# the compose/standalone forms), so the chain builds in order in one invocation.
FROM base

# golang-go is Ubuntu's Go; build-essential/pkg-config keep cgo builds working.
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential golang-go pkg-config \
 && rm -rf /var/lib/apt/lists/*

# Module and build caches live in the image's own filesystem, so the project
# mount holds source only and `go install` inside the box stays free (D8).
ENV GOPATH=/root/go \
    GOMODCACHE=/root/go/pkg/mod \
    GOCACHE=/root/.cache/go-build
