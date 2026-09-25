# syntax=docker/dockerfile:1
# devbox lisp — SBCL + slr. Toolchain only: this file names no agent and no
# harness (D2, criterion 7); the harness slot is filled by images/base.
#
# The base layer arrives as the named build context `base`: that is what lets
# one compose invocation build the chain in order, with no tag convention
# (slice 3: `additional_contexts: {base: service:base}`). A standalone build
# passes `--build-context base=docker-image://devbox/base:local`.
#
# slr's own repo is private and this repo is public, so its source arrives as a
# named build context too — never vendored here, never fetched with a credential
# (I4, I5), never mounted from the host (I1):
#   git -C <slr checkout> archive HEAD | tar -x -C "$SLR_SRC"
FROM base

# sbcl builds slr's core here; git is what slr uses to resolve projects.
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && apt-get install -y --no-install-recommends sbcl \
 && rm -rf /var/lib/apt/lists/*

# install.sh copies bin/ lib/ build/ into /usr/local and rebuilds slr.core
# against this image's SBCL: the core from a macOS checkout is never used.
COPY --from=slr / /usr/local/src/slr
RUN sh /usr/local/src/slr/install.sh --prefix=/usr/local
