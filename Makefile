PROJECT=socios
ORGANISATION=socios-linux
BIN=$(PROJECT)
GOVERSION := 1.15.2
BUILDDATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
COMMITHASH := $(shell git rev-parse HEAD)
VERSION := $(shell (test -f VERSION && cat VERSION) || echo "")
SOURCE=$(shell find . -name '*.go')
USERID=$(shell id -u)
GROUPID=$(shell id -g)

ifndef GOOS
	GOOS := $(shell go env GOOS)
endif
ifndef GOARCH
	GOARCH := $(shell go env GOARCH)
endif

# binary to test with
TESTBIN := build/bin/${BIN}-${GOOS}-${GOARCH}

.PHONY: clean build test crosscompile

all: build

# install and execute packr in a way that works both locally and in CI
prebuild:
	mkdir -p $(shell pwd)/go-build-cache
	chown -R ${USERID}:${GROUPID} $(shell pwd)/go-build-cache
	docker run --rm \
		-v $(shell pwd):/go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		-v $(shell pwd)/go-build-cache:/.cache \
		-e GOPATH=/go -e GOOS=linux -e GOARCH=amd64 \
		-w /go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		--user ${USERID}:${GROUPID} \
		golang:$(GOVERSION)-alpine /bin/sh -c "go install github.com/gobuffalo/packr/packr && packr"

# build binary for current platform
build: prebuild build/bin/$(BIN)-$(GOOS)-$(GOARCH)

# install binary for current platform (not expected to work on Win)
install: build
	cp build/bin/$(BIN)-$(GOOS)-$(GOARCH) /usr/local/bin/$(BIN)

# build for all platforms
crosscompile: prebuild build/bin/$(BIN)-darwin-amd64 build/bin/$(BIN)-linux-amd64

# platform-specific build
build/bin/$(BIN)-darwin-amd64: $(SOURCE)
	@mkdir -p build/bin
	@mkdir -p go-build-cache
	@echo "Commit hash: $(COMMITHASH)"
	docker run --rm \
		-v $(shell pwd):/go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		-v $(shell pwd)/go-build-cache:/.cache \
		-e GOPATH=/go -e GOOS=darwin -e GOARCH=amd64 -e CGO_ENABLED=0 \
		-w /go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		--user ${USERID}:${GROUPID} \
		golang:$(GOVERSION)-alpine go build -a -installsuffix cgo -o build/bin/$(BIN)-darwin-amd64 \
		-ldflags="-X github.com/socios-linux/socios/buildinfo.Version=$(VERSION) -X github.com/socios-linux/socios/buildinfo.BuildDate=$(BUILDDATE) -X github.com/socios-linux/socios/buildinfo.Commit=$(COMMITHASH)"
	rm -rf go-build-cache

# platform-specific build for linux-amd64
# CGO disabled on purpose, to enable support for Docker containers, specifically those based on Alpine.
build/bin/$(BIN)-linux-amd64: $(SOURCE)
	@mkdir -p build/bin
	@mkdir -p go-build-cache
	docker run --rm \
		-v $(shell pwd):/go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		-v $(shell pwd)/go-build-cache:/.cache \
		-e GOPATH=/go -e GOOS=linux -e GOARCH=amd64 -e CGO_ENABLED=0 \
		-w /go/src/github.com/$(ORGANISATION)/$(PROJECT) \
		--user ${USERID}:${GROUPID} \
		golang:$(GOVERSION)-buster go build -a -o build/bin/$(BIN)-linux-amd64 \
		-ldflags="-X github.com/socios-linux/socios/buildinfo.Version=$(VERSION) -X github.com/socios-linux/socios/buildinfo.BuildDate=$(BUILDDATE) -X github.com/socios-linux/socios/buildinfo.Commit=$(COMMITHASH)"
	rm -rf go-build-cache

gotest:
	go test -cover ./...

# run some tests
test: $(TESTBIN)
	@${TESTBIN} >> /dev/null && echo "OK"
	@${TESTBIN} help >> /dev/null && echo "OK"
	@${TESTBIN} --help >> /dev/null && echo "OK"
	@${TESTBIN} -h >> /dev/null && echo "OK"

	@${TESTBIN} create --help >> /dev/null && echo "OK"
	@${TESTBIN} info --help >> /dev/null && echo "OK"
	@${TESTBIN} list --help >> /dev/null && echo "OK"
	@${TESTBIN} login --help >> /dev/null && echo "OK"
	@${TESTBIN} logout --help >> /dev/null && echo "OK"
	@${TESTBIN} ping --help >> /dev/null && echo "OK"

	# @${TESTBIN} ping >> /dev/null && echo "OK"
	@${TESTBIN} info >> /dev/null && echo "OK"

# Create binary files for releases
bin-dist: crosscompile
	mkdir -p bin-dist

	for OS in darwin-amd64 linux-amd64; do \
		mkdir -p build/$(BIN)-$(VERSION)-$$OS; \
		cp README.md build/$(BIN)-$(VERSION)-$$OS/; \
		cp LICENSE build/$(BIN)-$(VERSION)-$$OS/; \
		cp build/bin/$(BIN)-$$OS build/$(BIN)-$(VERSION)-$$OS/$(BIN); \
		cd build/; \
		tar -cvzf ./$(BIN)-$(VERSION)-$$OS.tar.gz $(BIN)-$(VERSION)-$$OS; \
		mv ./$(BIN)-$(VERSION)-$$OS.tar.gz ../bin-dist/; \
		cd ..; \
	done


# remove generated stuff
clean:
	rm -rf bin-dist build go-build-cache release ./socios
