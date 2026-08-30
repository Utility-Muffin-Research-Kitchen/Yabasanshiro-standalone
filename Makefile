SHELL := /bin/bash

DOCKER ?= docker
TOOLCHAIN_IMAGE ?= ghcr.io/utility-muffin-research-kitchen/mlp1-toolchain:local
HOST_TOOLS_IMAGE ?= gcc@sha256:3e239a5ea77200b9163c825a0a5ebc17ca99f3bbb4d08241ee0fb9c174325880
BUILD_JOBS ?=
MLP1_BUILD_PROFILE ?= perf

.PHONY: fetch-upstream build-host-tools build-mlp1 verify-mlp1 \
	package-mlp1 verify-package-mlp1 smoke-launch-wrapper clean

fetch-upstream:
	./scripts/fetch-upstream.sh

build-host-tools: fetch-upstream
	DOCKER="$(DOCKER)" HOST_TOOLS_IMAGE="$(HOST_TOOLS_IMAGE)" \
		./scripts/build-host-tools.sh

build-mlp1:
	DOCKER="$(DOCKER)" \
	TOOLCHAIN_IMAGE="$(TOOLCHAIN_IMAGE)" \
	HOST_TOOLS_IMAGE="$(HOST_TOOLS_IMAGE)" \
	BUILD_JOBS="$(BUILD_JOBS)" \
	MLP1_BUILD_PROFILE="$(MLP1_BUILD_PROFILE)" \
		./build-mlp1.sh

verify-mlp1: build-mlp1
	DOCKER="$(DOCKER)" TOOLCHAIN_IMAGE="$(TOOLCHAIN_IMAGE)" \
		./scripts/verify-mlp1-binary.sh

package-mlp1: build-mlp1
	./package-mlp1.sh

verify-package-mlp1:
	./scripts/verify-mlp1-package.sh

smoke-launch-wrapper:
	./scripts/smoke-launch-wrapper.sh

clean:
	rm -rf output/mlp1
