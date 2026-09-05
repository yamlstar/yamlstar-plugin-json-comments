M ?= .cache/makes
$(shell test -d $M || git clone -q https://github.com/makeplus/makes $M)
include $M/init.mk
include $M/gloat.mk
include $M/go.mk
include $M/babashka.mk
include $M/perl.mk
include $M/clean.mk

VERSION := 0.1.0
MODULE := github.com/yaml/yamlstar-plugin-json-comments
YAMLSTAR_DIR ?= ../..
YAML_PARSER_DIR ?= ../yaml-reference-parser-clj

UNAME_S := $(shell uname -s)
SO := $(if $(filter Darwin,$(UNAME_S)),dylib,so)
LIB := lib/libyamlstar-plugin-json-comments.$(SO)
GENERATED_WORK := .cache/generated
GENERATED_DIR := internal/glojure
SOURCE_CACHE := .cache/src

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
  lib

default:: build

build: $(LIB)

test: $(LIB)
	$(BB) -cp src:$(YAML_PARSER_DIR)/src:test \
	  -m yamlstar-plugin.json-comments-test
	$(GO) test ./...
	$(CC) -Wall -Wextra -Werror -Iinclude \
	  -DPLUGIN_EXTENSION='"$(SO)"' test/abi.c \
	  $(if $(filter Darwin,$(UNAME_S)),,-ldl) -pthread -o .cache/abi-test
	YAMLSTAR_PLUGIN_PATH=$(abspath lib) .cache/abi-test

$(SOURCE_CACHE)/yaml_parser/%.clj: \
  $(YAML_PARSER_DIR)/src/yaml_parser/%.cljc
	@mkdir -p $(dir $@)
	ln -sf $(abspath $<) $@

$(GENERATED_DIR)/.generated: $(GLOAT_SOURCES) $(GLOAT)
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

$(LIB): $(GENERATED_DIR)/.generated main.go go.mod
	@mkdir -p $(dir $@)
	$(GO) build -buildmode=c-shared -o $@ .

format:
	$(GO) fmt ./...

install: $(LIB)
	install -d $(PREFIX)/lib/yamlstar/plugins
	install -m 755 $(LIB) $(PREFIX)/lib/yamlstar/plugins/
