# Android native test project -- developer entry points.
#
# The Gradle wrapper is the primary build. `make apk-raw` is a dependency-free
# fallback that uses the SDK command-line tools directly.

SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ENV_RUN     := $(ROOT)/scripts/env-run.sh
GRADLE      := $(ROOT)/gradlew
CC          ?= cc
APP_ID      := $(shell sed -n 's/^android\.applicationId=//p' "$(ROOT)/gradle.properties" | tail -n 1)
ifeq ($(strip $(APP_ID)),)
APP_ID      := com.example.nativeapp
endif
APK_DEBUG   := $(ROOT)/app/build/outputs/apk/debug/app-debug.apk
GRADLE_OPTS ?= --console=plain

.PHONY: help bootstrap doctor wrapper wrapper-force local-properties \
        test test-sanitize apk apk-raw release install install-raw run run-raw \
        log devices require-device connected-test uninstall clean distclean \
        check lint all

help: ## Show this help
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' \
		"$(lastword $(MAKEFILE_LIST))"
	@echo
	@echo "Typical flow:"
	@echo "  make bootstrap     # once: install SDK/NDK/CMake + gradlew"
	@echo "  make doctor        # verify the toolchain"
	@echo "  make test          # host C unit tests (no device needed)"
	@echo "  make apk           # debug APK via Gradle"
	@echo "  make install       # install on the connected device"
	@echo "  make run           # build, install and launch"

bootstrap: ## Install SDK packages and generate the Gradle wrapper
	@"$(ROOT)/bootstrap.sh"

doctor: ## Check JDK, SDK, NDK, CMake, adb and the Gradle wrapper
	@"$(ROOT)/scripts/doctor.sh"

wrapper: ## Generate gradlew (one-time; needs a system Gradle)
	@"$(ROOT)/scripts/generate-wrapper.sh"

wrapper-force: ## Regenerate gradlew even if it already exists
	@"$(ROOT)/scripts/generate-wrapper.sh" --force

local-properties: ## Create local.properties from ANDROID_HOME when missing
	@"$(ROOT)/scripts/ensure-local-properties.sh"

test: ## Build and run the host-side C unit tests
	@mkdir -p "$(ROOT)/build/host"
	@"$(ENV_RUN)" $(CC) -std=c11 -O0 -g -Wall -Wextra -Werror \
		-I"$(ROOT)/app/src/main/cpp" \
		"$(ROOT)/tests/test_core.c" "$(ROOT)/app/src/main/cpp/core.c" \
		-o "$(ROOT)/build/host/test_core"
	@"$(ROOT)/build/host/test_core"

test-sanitize: ## Run host tests with ASan + UBSan
	@mkdir -p "$(ROOT)/build/host"
	@"$(ENV_RUN)" $(CC) -std=c11 -O1 -g -Wall -Wextra -Werror \
		-fsanitize=address,undefined -fno-omit-frame-pointer \
		-I"$(ROOT)/app/src/main/cpp" \
		"$(ROOT)/tests/test_core.c" "$(ROOT)/app/src/main/cpp/core.c" \
		-o "$(ROOT)/build/host/test_core_sanitize"
	@"$(ROOT)/build/host/test_core_sanitize"

$(GRADLE):
	@"$(ROOT)/scripts/generate-wrapper.sh"

apk: local-properties $(GRADLE) ## Build the debug APK with Gradle
	@"$(ENV_RUN)" "$(GRADLE)" $(GRADLE_OPTS) :app:assembleDebug
	@echo "APK: $(APK_DEBUG)"

apk-raw: ## Build the debug APK without Gradle (SDK command-line tools only)
	@"$(ROOT)/build.sh" build

release: local-properties $(GRADLE) ## Build a release APK (signed with the debug key locally)
	@"$(ENV_RUN)" "$(GRADLE)" $(GRADLE_OPTS) :app:assembleRelease
	@echo "APK: $(ROOT)/app/build/outputs/apk/release/app-release.apk"

require-device: ## Fail unless an adb device is attached
	@"$(ROOT)/scripts/require-device.sh"

devices: ## List connected devices
	@"$(ENV_RUN)" adb devices -l

install: require-device apk ## Install the debug APK on the connected device
	@"$(ENV_RUN)" adb install -r "$(APK_DEBUG)"

run: require-device install ## Build, install and launch on the connected device
	@"$(ENV_RUN)" adb shell am start -W -n "$(APP_ID)/.MainActivity"

install-raw: ## Install the fallback APK (builds it if missing)
	@"$(ROOT)/build.sh" install

run-raw: ## Same as `run`, using the Gradle-free build
	@"$(ROOT)/build.sh" run

log: ## Stream app + crash logs from the device
	@"$(ENV_RUN)" adb logcat -s NativeApp:V AndroidRuntime:E

connected-test: require-device apk ## Run instrumentation tests on a device
	@"$(ENV_RUN)" "$(GRADLE)" $(GRADLE_OPTS) :app:connectedDebugAndroidTest

uninstall: require-device ## Remove the app from the device
	@"$(ENV_RUN)" adb uninstall $(APP_ID)

clean: ## Remove build outputs (keeps caches and the wrapper)
	@rm -rf "$(ROOT)/build" "$(ROOT)/app/build" "$(ROOT)/app/.cxx"
	@echo "cleaned build outputs"

distclean: clean ## Also remove Gradle caches, local.properties and IDE files
	@rm -rf "$(ROOT)/.gradle" "$(ROOT)/.idea" "$(ROOT)/local.properties"
	@find "$(ROOT)" -name '*.iml' -delete
	@echo "removed caches and local configuration"

lint: local-properties $(GRADLE) ## Run Android Lint on the debug variant
	@"$(ENV_RUN)" "$(GRADLE)" $(GRADLE_OPTS) :app:lintDebug

check: test apk ## Host tests + debug APK
	@echo "check: ok"

all: check ## Alias for check
