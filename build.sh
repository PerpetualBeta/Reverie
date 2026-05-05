#!/bin/bash
# Thin wrapper around `make build` so Release Manager — which calls each
# project's `build.sh` — gets a consistent entry point. Local development
# typically uses `make run` (test-app) or `make install` (saver bundle).
set -e
cd "$(dirname "$0")"
make build
