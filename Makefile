SHELL:=/usr/bin/env bash

TAG:=$(notdir $(CURDIR))
PYVER:=$(shell grep -oP 'ARG PYVER=\K.*' Dockerfile)
GDVER:=$(shell grep -oP 'ARG GDVER=\K.*' Dockerfile)
REL=$(TAG):$(PYVER)-gdal$(GDVER)

.PHONY: run bash push tag build force

run: build
	docker run --rm -it $(TAG)

bash: build
	docker run --rm -it $(TAG) bash

push: build tag
	docker tag $(TAG) dotysan/$(TAG)
	docker tag $(REL) dotysan/$(REL)
	docker push dotysan/$(TAG)
	docker push dotysan/$(REL)

tag: build
	docker tag $(TAG) $(REL)

build:
	docker build --progress=plain --tag $(TAG) .
force:
	docker build --progress=plain --tag $(TAG) --no-cache .
