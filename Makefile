### Makefile for tidb-lightning

GOPATH ?= $(shell go env GOPATH)

# Ensure GOPATH is set before running build process.
ifeq "$(GOPATH)" ""
  $(error Please set the environment variable GOPATH before running `make`)
endif

LDFLAGS += -X "github.com/pingcap/tidb-lightning/lightning/common.ReleaseVersion=$(shell git describe --tags --dirty="-dev")"
LDFLAGS += -X "github.com/pingcap/tidb-lightning/lightning/common.BuildTS=$(shell date -u '+%Y-%m-%d %I:%M:%S')"
LDFLAGS += -X "github.com/pingcap/tidb-lightning/lightning/common.GitHash=$(shell git rev-parse HEAD)"
LDFLAGS += -X "github.com/pingcap/tidb-lightning/lightning/common.GitBranch=$(shell git rev-parse --abbrev-ref HEAD)"
LDFLAGS += -X "github.com/pingcap/tidb-lightning/lightning/common.GoVersion=$(shell go version)"

LIGHTNING_BIN := bin/tidb-lightning
LIGHTNING_CTL_BIN := bin/tidb-lightning-ctl
TEST_DIR := /tmp/lightning_test_result
# this is hard-coded unless we want to generate *.toml on fly.

TIDBDIR := vendor/github.com/pingcap/tidb
path_to_add := $(addsuffix /bin,$(subst :,/bin:,$(GOPATH)))
export PATH := $(path_to_add):$(PATH)

GO        := go
GOBUILD   := GO111MODULE=off CGO_ENABLED=0 $(GO) build
GOTEST    := GO111MODULE=off CGO_ENABLED=1 $(GO) test -p 3

ARCH      := "`uname -s`"
LINUX     := "Linux"
MAC       := "Darwin"
PACKAGES  := $$(go list ./...| grep -vE 'vendor|cmd|test|proto|diff|bin')

RACE_FLAG =
ifeq ("$(WITH_RACE)", "1")
	RACE_FLAG = -race
	GOBUILD   = GOPATH=$(GOPATH) CGO_ENABLED=1 $(GO) build
endif

.PHONY: all build parser clean lightning lightning-ctl test integration_test

default: clean lightning lightning-ctl checksuccess

build:
	$(GOBUILD)

clean:
	$(GO) clean -i ./...
	rm -f $(LIGHTNING_BIN) $(LIGHTNING_CTRL_BIN)

checksuccess:
	@if [ -f $(LIGHTNING_BIN) ] && [ -f $(LIGHTNING_CTRL_BIN) ]; \
	then \
		echo "Lightning build successfully :-) !" ; \
	fi

lightning:
	$(GOBUILD) $(RACE_FLAG) -ldflags '$(LDFLAGS)' -o $(LIGHTNING_BIN) cmd/main.go

lightning-ctl:
	$(GOBUILD) $(RACE_FLAG) -ldflags '$(LDFLAGS)' -o $(LIGHTNING_CTL_BIN) cmd/tidb-lightning-ctl/main.go

test:
	mkdir -p "$(TEST_DIR)"
	@export log_level=error;\
	$(GOTEST) -cover -covermode=count -coverprofile="$(TEST_DIR)/cov.unit.out" $(PACKAGES)

integration_test:
	@which bin/tidb-server
	@which bin/tikv-server
	@which bin/pd-server
	@which bin/tikv-importer
	$(GOTEST) -c -cover -covermode=count \
		-coverpkg=github.com/pingcap/tidb-lightning/... \
		-o bin/tidb-lightning.test \
		github.com/pingcap/tidb-lightning/cmd
	$(GOBUILD) -o bin/importer_proxy tests/_utils/importer_proxy.go
	tests/run.sh

coverage:
	GO111MODULE=off go get github.com/wadey/gocovmerge
	gocovmerge "$(TEST_DIR)"/cov.* > "$(TEST_DIR)/all_cov.out"
	go tool cover -html "$(TEST_DIR)/all_cov.out" -o "$(TEST_DIR)/all_cov.html"
	grep -F '<option' "$(TEST_DIR)/all_cov.html"

update: update_vendor clean_vendor
update_vendor:
	rm -rf vendor/
	GO111MODULE=on go mod verify
	GO111MODULE=on go mod vendor

clean_vendor:
	hack/clean_vendor.sh
