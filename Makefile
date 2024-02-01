SHELL:=/usr/bin/env bash

TAG:=$(notdir $(CURDIR))

.PHONY: run bash build

run: build
	docker run --rm -it $(TAG)

bash: build
	docker run --rm -it $(TAG) bash

build:
	docker build --progress=plain --tag $(TAG) .
