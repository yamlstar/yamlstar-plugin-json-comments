MAKES-COMMIT := e4d2756ed838f3df16f1e33f20c993bd030ef01a
M ?= .cache/makes
$(shell test -d $M || { \
  git clone -q https://github.com/makeplus/makes $M && \
  git -C $M checkout -q $(MAKES-COMMIT); \
})

GO-VERSION := 1.27.1
GLOAT-VERSION := 0.1.79
BABASHKA-VERSION := 1.13.220
PERL-VERSION := 5.44.0.0

include $M/init.mk
include $M/gloat.mk
include $M/go.mk
include $M/babashka.mk
include $M/perl.mk
include $M/docker.mk
include $M/clean.mk

VERSION := 0.1.0
MODULE := github.com/yamlstar/yamlstar-plugin-json-comments
YAML-PARSER-COMMIT := a867cac0568aeb453f9bfae0b2339da983019d07
YAML_PARSER_DIR ?= $(patsubst %/src/yaml_parser/core.clj,%, \
  $(firstword \
    $(wildcard \
      repos/yaml-reference-parser-clj/src/yaml_parser/core.clj \
      ../yaml-reference-parser-clj/src/yaml_parser/core.clj)))

PLUGIN := yamlstar-plugin-json-comments
LIB-NAME := lib$(PLUGIN).$(SO)
LIB := lib/$(LIB-NAME)
GENERATED_WORK := .cache/generated
GENERATED_DIR := internal/glojure
SOURCE_CACHE := .cache/src
RELEASE_LIB_DIR := .cache/release/lib
RELEASE_LIB := $(RELEASE_LIB_DIR)/$(LIB-NAME)

RELEASE-ARCH := $(if $(IS-INTEL),x64,\
  $(if $(IS-LINUX),aarch64,arm64))
RELEASE_PLATFORM ?= $(OS-NAME)-$(RELEASE-ARCH)
RELEASE_NAME := $(PLUGIN)-$(VERSION)-$(RELEASE_PLATFORM)
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
CONTAINER-PARSER-DIR := /yaml-reference-parser-clj

PARSER_SOURCES := \
  $(SOURCE_CACHE)/yaml_parser/prelude.clj \
  $(SOURCE_CACHE)/yaml_parser/parser.clj \
  $(SOURCE_CACHE)/yaml_parser/receiver.clj \
  $(SOURCE_CACHE)/yaml_parser/grammar.clj \
  $(YAML_PARSER_DIR)/src/yaml_parser/core.clj

GLOAT_SOURCES := \
  $(PARSER_SOURCES) \
  src/yamlstar_plugin/json_comments.clj

MAKES-CLEAN := \
  $(SOURCE_CACHE) \
  $(GENERATED_WORK) \
  $(GENERATED_DIR) \
  $(RELEASE_LIB_DIR) \
  dist \
  lib

default:: build

build: $(LIB)

test: $(LIB) $(BB)
	$(BB) -cp src:$(YAML_PARSER_DIR)/src:test \
	  -m yamlstar-plugin.json-comments-test
	$(GO) test ./...
	$(call compile-abi-test,.cache/abi-test)
	YAMLSTAR_PLUGIN_PATH=$(abspath lib) .cache/abi-test

test-release: $(RELEASE_LIB)
	$(call compile-abi-test,.cache/release-abi-test)
	YAMLSTAR_PLUGIN_PATH=$(abspath $(RELEASE_LIB_DIR)) \
	  .cache/release-abi-test

test-archive: $(PERL)
	test -n "$(ARCHIVE)"
	PERL=$(PERL-LOCAL)/bin/perl CC="$(CC)" util/test-archive \
	  "$(ARCHIVE)" "$(RELEASE_PLATFORM)" "$(VERSION)"

release-check:
	[[ "$(VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]
	test -n "$(YAML_PARSER_DIR)"
	test -f "$(YAML_PARSER_DIR)/src/yaml_parser/core.clj"
	test "$$(git -C $(YAML_PARSER_DIR) rev-parse HEAD)" = \
	  "$(YAML-PARSER-COMMIT)"
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
	  -e BUILD_UID="$$(id -u)" \
	  -e BUILD_GID="$$(id -g)" \
	  -v "$(CURDIR):/work" \
	  -v "$(abspath $(YAML_PARSER_DIR)):$(CONTAINER-PARSER-DIR):ro" \
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
	    dnf install -y binutils file git make perl xz >/dev/null; \
	    git config --global --add safe.directory /work; \
	    git config --global --add safe.directory /work/.cache/makes; \
	    git config --global --add safe.directory \
	      $(CONTAINER-PARSER-DIR); \
	    make release-archive \
	      VERSION="$$VERSION" \
	      RELEASE_PLATFORM="$$RELEASE_PLATFORM" \
	      YAML_PARSER_DIR=$(CONTAINER-PARSER-DIR); \
	  '

release-archive: $(ARCHIVE)

$(ARCHIVE): release-check test-release plugin.edn \
  include/yamlstar_plugin.h License ReadMe.md util/test-archive
	rm -rf "$(RELEASE_DIR)" "$@"
	install -d \
	  "$(RELEASE_DIR)/lib/yamlstar/plugins" \
	  "$(RELEASE_DIR)/include/yamlstar" \
	  "$(RELEASE_DIR)/share/yamlstar/plugins/json-comments"
	install -m 755 "$(RELEASE_LIB)" \
	  "$(RELEASE_DIR)/lib/yamlstar/plugins/$(LIB-NAME)"
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

$(SOURCE_CACHE)/yaml_parser/%.clj: \
  $(YAML_PARSER_DIR)/src/yaml_parser/%.cljc
	@mkdir -p $(dir $@)
	$(RM) "$@"
	cp "$<" "$@"

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

$(LIB): $(GENERATED_DIR)/.generated main.go plugin.edn go.mod $(GO)
	@mkdir -p $(dir $@)
	$(GO) build -buildmode=c-shared -o $@ .

$(RELEASE_LIB): $(GENERATED_DIR)/.generated main.go plugin.edn go.mod $(GO)
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
	install -d $(PREFIX)/lib/yamlstar/plugins
	install -m 755 $(LIB) $(PREFIX)/lib/yamlstar/plugins/
