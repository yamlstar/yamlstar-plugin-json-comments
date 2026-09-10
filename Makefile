MAKES-COMMIT := a7b80ec8f10ac700693278a559f315fccd50b5ad
M ?= .cache/makes
$(shell test -d $M || { \
  git clone -q https://github.com/makeplus/makes $M && \
  git -C $M checkout -q $(MAKES-COMMIT); \
})

GO-VERSION := 1.27.1
BABASHKA-VERSION := 1.13.220
PERL-VERSION := 5.44.0.0
export UV_CACHE_DIR := $(CURDIR)/.cache/uv

include $M/init.mk
include $M/gh.mk
include $M/gloat.mk
include $M/go.mk
include $M/babashka.mk
include $M/perl.mk
include $M/docker.mk
include $M/clean.mk
include $M/shellcheck.mk

# Correct uv-managed CPython names until Makes provides these mappings.
CPYTHON-OA-linux-arm64 := linux-aarch64-gnu
CPYTHON-OA-macos-int64 := macos-x86_64-none
ifneq ($(CPYTHON-OA-$(OS-ARCH)),)
override PYTHON-NAME = \
  cpython-$(PYTHON-VERSION)-$(CPYTHON-OA-$(OS-ARCH))
endif
include $M/python.mk
include $M/shell.mk

PYTHON-VENV-SETUP := \
  $(UV) pip install --python $(PYTHON-VENV) setuptools wheel

VERSION := 0.1.4
MODULE := github.com/yamlstar/yamlstar-plugin-json-comments
YAML-PARSER-VERSION := 0.2.4
YAML-PARSER-FILE := yaml-parser-$(YAML-PARSER-VERSION).jar
YAML-PARSER-JAR := .cache/$(YAML-PARSER-FILE)
YAML-PARSER-BASE-URL := https://repo.clojars.org/org/yamlstar/yaml-parser
YAML-PARSER-URL := $(YAML-PARSER-BASE-URL)/$(YAML-PARSER-VERSION)
YAML-PARSER-URL := $(YAML-PARSER-URL)/$(YAML-PARSER-FILE)
YAML-PARSER-SRC-DIR := .cache/yaml-parser-$(YAML-PARSER-VERSION)
YAML-PARSER-SRC-STAMP := $(YAML-PARSER-SRC-DIR)/.extracted

PLUGIN := yamlstar-plugin-json-comments
LIB-NAME := lib$(PLUGIN).$(SO)
LIB := lib/$(LIB-NAME)
GENERATED_WORK := .cache/generated
GENERATED_DIR := internal/glojure
USE_GENERATED_SOURCES ?=
SOURCE_CACHE := .cache/src
RELEASE_LIB_DIR := .cache/release/lib
RELEASE_LIB := $(RELEASE_LIB_DIR)/$(LIB-NAME)
WHEEL-PACKAGE := yamlstar_plugin_json_comments
WHEEL-PACKAGE-DIR := python/lib/$(WHEEL-PACKAGE)
WHEEL-LIB-DIR := $(WHEEL-PACKAGE-DIR)/lib
WHEEL-CACHE := .cache/wheel
WHEEL-SOURCE-LIB = \
  $(WHEEL-CACHE)/$(RELEASE_NAME)/lib/$(LIB-NAME)
WHEEL-PLAT-linux-x64 := manylinux_2_28_x86_64
WHEEL-PLAT-linux-aarch64 := manylinux_2_28_aarch64
WHEEL-PLAT-macos-x64 := macosx_15_0_x86_64
WHEEL-PLAT-macos-arm64 := macosx_14_0_arm64
WHEEL-PLAT := $(WHEEL-PLAT-$(RELEASE_PLATFORM))
WHEEL-TAG := py3-none-$(WHEEL-PLAT)
WHEEL-FILE := python/dist/$(WHEEL-PACKAGE)-$(VERSION)-$(WHEEL-TAG).whl
WHEEL ?= $(WHEEL-FILE)
WHEEL-TEST-VENV := .cache/wheel-test
WHEEL-TEST-PYTHON := $(WHEEL-TEST-VENV)/bin/python

RELEASE-ARCH := $(if $(IS-INTEL),x64,\
  $(if $(IS-LINUX),aarch64,arm64))
RELEASE_PLATFORM ?= $(OS-NAME)-$(RELEASE-ARCH)
RELEASE_NAME := $(PLUGIN)-$(VERSION)-$(RELEASE_PLATFORM)
WHEEL-STAGE := $(WHEEL-CACHE)/$(RELEASE_NAME)/.staged
RELEASE_DIR := dist/$(RELEASE_NAME)
ARCHIVE := dist/$(RELEASE_NAME).tar.xz
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct)
TAR ?= $(if $(IS-MACOS),gtar,tar)
MANYLINUX-REPO-linux-x64 := quay.io/pypa/manylinux_2_28_x86_64
MANYLINUX-REPO-linux-aarch64 := quay.io/pypa/manylinux_2_28_aarch64
MANYLINUX-DIGEST-linux-x64 := \
  sha256:53390351aeb4688114b02c36a23b3e6ce1166ee9b7afc5df1a4f776354fc764c
MANYLINUX-DIGEST-linux-aarch64 := \
  sha256:ad74e53b713f3b07d8c889c526dc0c6500da9827b45e38739570875fef52e28f
MANYLINUX-REPO := $(MANYLINUX-REPO-$(RELEASE_PLATFORM))
MANYLINUX-DIGEST := $(MANYLINUX-DIGEST-$(RELEASE_PLATFORM))
MANYLINUX-IMAGE := $(MANYLINUX-REPO)@$(MANYLINUX-DIGEST)
RELEASE-REPO := yamlstar/yamlstar-plugin-json-comments
RELEASE-WORKFLOW := release.yaml
RELEASE-SCRIPT := util/release
RELEASE-CMD = \
  PERL=$(PERL-LOCAL)/bin/perl \
  GH=$(GH) \
  RELEASE_REPO=$(RELEASE-REPO) \
  RELEASE_WORKFLOW=$(RELEASE-WORKFLOW) \
  $(RELEASE-SCRIPT)

PARSER_SOURCES := \
  $(SOURCE_CACHE)/yaml_parser/prelude.clj \
  $(SOURCE_CACHE)/yaml_parser/parser.clj \
  $(SOURCE_CACHE)/yaml_parser/receiver.clj \
  $(SOURCE_CACHE)/yaml_parser/grammar.clj \
  $(SOURCE_CACHE)/yaml_parser/core.clj

GLOAT_SOURCES := \
  $(PARSER_SOURCES) \
  src/yamlstar_plugin/json_comments.clj

MAKES-CLEAN := \
  $(YAML-PARSER-JAR) \
  $(YAML-PARSER-SRC-DIR) \
  $(SOURCE_CACHE) \
  $(WHEEL-CACHE) \
  $(WHEEL-TEST-VENV) \
  $(GENERATED_WORK) \
  $(GENERATED_DIR) \
  $(RELEASE_LIB_DIR) \
  dist \
  lib \
  python/build \
  python/dist \
  python/*.egg-info \
  python/lib/*.egg-info \
  $(WHEEL-LIB-DIR) \
  $(WHEEL-PACKAGE-DIR)/plugin.edn \
  $(WHEEL-PACKAGE-DIR)/License

default:: build

build: $(LIB)

generate: $(GENERATED_DIR)/.generated

test: $(LIB) $(PARSER_SOURCES) $(BB) $(SHELLCHECK)
	$(BB) -cp src:$(SOURCE_CACHE):test \
	  -m yamlstar-plugin.json-comments-test
	$(GO) test ./...
	$(call compile-abi-test,.cache/abi-test)
	YAMLSTAR_LIBRARY_PATH=$(abspath lib) .cache/abi-test
	$(SHELLCHECK) util/release util/test-archive

benchmark: $(LIB)
	YAMLSTAR_PERFORMANCE_TEST=1 $(GO) test \
	  -run '^TestPerformance$$' -count=1 -timeout=45s -v

benchmark-binary: $(LIB)
	$(GO) test -run '^$$' -bench '^BenchmarkTransport$$' \
	  -benchtime=1x -count=7 -timeout=30m

binary-sizes: $(LIB)
	YAMLSTAR_BINARY_SIZES=1 $(GO) test \
	  -run '^TestBinaryWireSizes$$' -v -timeout=10m

# An EDN-only copy from identical sources exercises the legacy ABI path.
build-edn: $(LIB)
	mkdir -p .cache/edn-only
	$(GO) build -tags ednonly -buildmode=c-shared \
	  -o .cache/edn-only/$(LIB-NAME) .

wheel: dist
	$(MAKE) -o $(ARCHIVE) $(WHEEL-FILE) VERSION=$(VERSION) \
	  RELEASE_PLATFORM=$(RELEASE_PLATFORM)

test-wheel: $(WHEEL) $(UV) $(PYTHON)
	@test -n "$(WHEEL-PLAT)" || { \
	  echo "No wheel platform for $(RELEASE_PLATFORM)" >&2; \
	  exit 1; \
	}
	rm -rf $(WHEEL-CACHE)
	mkdir -p $(WHEEL-CACHE)
	tar -C $(WHEEL-CACHE) -xf $(ARCHIVE)
	test -f $(WHEEL-SOURCE-LIB)
	rm -rf $(WHEEL-TEST-VENV)
	$(UV) venv --python $(PYTHON) $(WHEEL-TEST-VENV)
	$(UV) pip install --python $(WHEEL-TEST-PYTHON) \
	  --force-reinstall $(WHEEL)
	$(call compile-abi-test,.cache/wheel-abi-test)
	library_dir="$$( \
	  $(WHEEL-TEST-PYTHON) python/test_wheel.py \
	    $(WHEEL) $(WHEEL-TAG) $(WHEEL-SOURCE-LIB) \
	    $(VERSION) \
	)"; \
	YAMLSTAR_LIBRARY_PATH="$$library_dir" .cache/wheel-abi-test

test-release: $(RELEASE_LIB)
	$(call compile-abi-test,.cache/release-abi-test)
	YAMLSTAR_LIBRARY_PATH=$(abspath $(RELEASE_LIB_DIR)) \
	  .cache/release-abi-test

test-archive: $(PERL)
	test -n "$(ARCHIVE)"
	PERL=$(PERL-LOCAL)/bin/perl CC="$(CC)" util/test-archive \
	  "$(ARCHIVE)" "$(RELEASE_PLATFORM)" "$(VERSION)"

release-check: $(YAML-PARSER-SRC-STAMP)
	[[ "$(VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]
	test -f "$(YAML-PARSER-SRC-DIR)/yaml_parser/core.clj"
	grep -Fq ':version "$(VERSION)"' plugin.edn
	test "$$(git -C $M rev-parse HEAD)" = "$(MAKES-COMMIT)"
	case "$(RELEASE_PLATFORM)" in \
	  linux-x64|linux-aarch64|macos-x64|macos-arm64) ;; \
	  *) echo "Unsupported release platform: $(RELEASE_PLATFORM)" >&2; \
	     exit 1 ;; \
	esac

ifeq ($(IS-LINUX),true)
dist: test release-linux
else
dist: test release-archive
endif

release-linux: | $(DOCKER)
	test -n "$(MANYLINUX-IMAGE)"
	$(DOCKER) run --rm \
	  -e VERSION="$(VERSION)" \
	  -e RELEASE_PLATFORM="$(RELEASE_PLATFORM)" \
	  -e USE_GENERATED_SOURCES="$(USE_GENERATED_SOURCES)" \
	  -e BUILD_UID="$$(id -u)" \
	  -e BUILD_GID="$$(id -g)" \
	  -v "$(CURDIR):/work" \
	  -w /work \
	  "$(MANYLINUX-IMAGE)" \
	  bash -c ' \
	    set -euo pipefail; \
	    cleanup() { \
	      for path in /work/.cache/release /work/dist; do \
	        test ! -e "$$path" || \
	          chown -R "$$BUILD_UID:$$BUILD_GID" "$$path"; \
	      done; \
	    }; \
	    trap cleanup EXIT; \
	    dnf install -y binutils curl file git make perl unzip xz >/dev/null; \
	    git config --global --add safe.directory /work; \
	    git config --global --add safe.directory /work/.cache/makes; \
	    make release-archive \
	      VERSION="$$VERSION" \
	      RELEASE_PLATFORM="$$RELEASE_PLATFORM" \
	      USE_GENERATED_SOURCES="$$USE_GENERATED_SOURCES"; \
	  '

release-archive: $(ARCHIVE)

export OLD_VERSION := $o
export NEW_VERSION := $(or $v,$n)
ifdef d
export YS_RELEASE_DRYRUN := 1
endif
ifdef a
export YS_RELEASE_ALLOW_BRANCH := 1
endif

release: $(PERL) $(GH)
ifndef v
	$(error 'make release' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) release "$(o)" "$(v)"

release-list: $(PERL)
	$(RELEASE-CMD) list

release-sanity-check: $(PERL)
ifndef v
	$(error 'make release-sanity-check' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) sanity-check "$(o)" "$(v)"

release-version-bump: $(PERL)
ifndef v
	$(error 'make release-version-bump' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) version-bump "$(o)" "$(v)"

release-pull: $(PERL)
	$(RELEASE-CMD) pull

release-commit: $(PERL)
ifndef v
	$(error 'make release-commit' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) commit "$(v)"

release-tag: $(PERL)
ifndef v
	$(error 'make release-tag' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) tag "$(v)"

release-push: $(PERL)
ifndef v
	$(error 'make release-push' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) push "$(v)"

release-build-github: $(PERL) $(GH)
ifndef v
	$(error 'make release-build-github' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) build-github "$(v)"

release-retry: $(PERL) $(GH)
ifndef v
	$(error 'make release-retry' requires v=NEW_VERSION)
endif
	$(RELEASE-CMD) retry "$(v)"

$(ARCHIVE): Makefile release-check test-release plugin.edn \
  include/yamlstar_plugin.h License ReadMe.md util/test-archive
	rm -rf "$(RELEASE_DIR)" "$@"
	install -d \
	  "$(RELEASE_DIR)/lib" \
	  "$(RELEASE_DIR)/include/yamlstar" \
	  "$(RELEASE_DIR)/share/yamlstar/plugins/json-comments"
	install -m 755 "$(RELEASE_LIB)" \
	  "$(RELEASE_DIR)/lib/$(LIB-NAME)"
	install -m 644 include/yamlstar_plugin.h \
	  "$(RELEASE_DIR)/include/yamlstar/"
	install -m 644 plugin.edn \
	  "$(RELEASE_DIR)/share/yamlstar/plugins/json-comments/"
	install -m 644 License ReadMe.md "$(RELEASE_DIR)/"
	COPYFILE_DISABLE=1 $(TAR) \
	  --sort=name \
	  --mtime="@$(SOURCE_DATE_EPOCH)" \
	  --owner=0 --group=0 --numeric-owner \
	  -C dist -cJf "$@" "$(RELEASE_NAME)"
	$(MAKE) test-archive ARCHIVE="$@" \
	  RELEASE_PLATFORM="$(RELEASE_PLATFORM)" VERSION="$(VERSION)"

$(WHEEL-STAGE): $(ARCHIVE) plugin.edn License python/setup.py \
  python/lib/$(WHEEL-PACKAGE)/__init__.py
	@test -n "$(WHEEL-PLAT)" || { \
	  echo "No wheel platform for $(RELEASE_PLATFORM)" >&2; \
	  exit 1; \
	}
	rm -rf $(WHEEL-CACHE) $(WHEEL-LIB-DIR)
	mkdir -p $(WHEEL-CACHE) $(WHEEL-LIB-DIR)
	tar -C $(WHEEL-CACHE) -xf $(ARCHIVE)
	cp -p $(WHEEL-CACHE)/$(RELEASE_NAME)/lib/$(LIB-NAME) \
	  $(WHEEL-LIB-DIR)/
	cp -p plugin.edn $(WHEEL-PACKAGE-DIR)/
	cp -p License $(WHEEL-PACKAGE-DIR)/
	touch $@

$(WHEEL-FILE): $(WHEEL-STAGE) $(PYTHON-VENV)
	rm -rf python/build python/dist python/*.egg-info \
	  python/lib/*.egg-info
	cd python && $(VENV) && \
	  python setup.py bdist_wheel --plat-name $(WHEEL-PLAT)
	test -f $@

$(YAML-PARSER-JAR):
	@mkdir -p $(dir $@)
	curl --fail --location --silent --show-error \
	  '$(YAML-PARSER-URL)' -o '$@.tmp'
	mv '$@.tmp' '$@'

$(YAML-PARSER-SRC-STAMP): $(YAML-PARSER-JAR)
	rm -rf $(YAML-PARSER-SRC-DIR)
	mkdir -p $(YAML-PARSER-SRC-DIR)
	unzip -oq $< 'yaml_parser/*.clj' 'yaml_parser/*.cljc' \
	  -d $(YAML-PARSER-SRC-DIR)
	touch $@

$(SOURCE_CACHE)/yaml_parser/%.clj: $(YAML-PARSER-SRC-STAMP)
	@mkdir -p $(dir $@)
	$(RM) "$@"
	cp "$(YAML-PARSER-SRC-DIR)/yaml_parser/$*.cljc" "$@"

$(SOURCE_CACHE)/yaml_parser/core.clj: $(YAML-PARSER-SRC-STAMP)
	@mkdir -p $(dir $@)
	$(RM) "$@"
	cp "$(YAML-PARSER-SRC-DIR)/yaml_parser/core.clj" "$@"

ifeq ($(USE_GENERATED_SOURCES),1)
$(GENERATED_DIR)/.generated:
	test -f $(GENERATED_DIR)/pkg/yamlstar_plugin/json_comments/loader.go
	touch $@
else
$(GENERATED_DIR)/.generated: go.mod $(GLOAT_SOURCES) $(GLOAT)
	rm -rf $(GENERATED_WORK)
	mkdir -p $(GENERATED_WORK)
	env -u GOROOT $(GLOAT) --force --module $(MODULE) \
	  -o $(GENERATED_WORK)/ \
	  $(GLOAT_SOURCES)
	test -f $(GENERATED_WORK)/pkg/yamlstar_plugin/json_comments/loader.go
	rm -rf $(GENERATED_DIR)
	mkdir -p $(GENERATED_DIR)
	cp -R $(GENERATED_WORK)/pkg $(GENERATED_DIR)/
	touch $@
endif

$(LIB): $(GENERATED_DIR)/.generated main.go binary.go plugin.edn \
  go.mod go.sum $(GO)
	@mkdir -p $(dir $@)
	$(GO) build -buildmode=c-shared -o $@ .

$(RELEASE_LIB): $(GENERATED_DIR)/.generated main.go binary.go plugin.edn \
  go.mod go.sum $(GO)
	@mkdir -p $(dir $@)
	$(GO) build -trimpath -ldflags='-s -w' \
	  -buildmode=c-shared -o $@ .

define compile-abi-test
	$(CC) -Wall -Wextra -Werror -Iinclude \
	  -DPLUGIN_EXTENSION='"$(SO)"' \
	  -DPLUGIN_VERSION='"$(VERSION)"' \
	  test/abi.c $(if $(IS-MACOS),,-ldl) -pthread -o $(1)
endef

format:
	$(GO) fmt ./...

install: $(LIB)
	install -d $(PREFIX)/lib
	install -m 755 $(LIB) $(PREFIX)/lib/
