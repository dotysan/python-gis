SHELL:=/usr/bin/env bash

TAG:=$(notdir $(CURDIR))
PYVER:=$(shell grep -oP 'ARG PYVER=\K.*' Dockerfile)
GDVER:=$(shell grep -oP 'ARG GDVER=\K.*' Dockerfile)
REL=$(TAG):$(PYVER)-gdal$(GDVER)
GID=$(shell id -g)

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
	docker build --progress=plain --tag $(TAG) . && \
	docker run --rm --volume=$$PWD:/mnt --user=$$UID:$(GID) $(TAG) sh -c 'cp /*.txt /mnt/'
force:
	docker build --progress=plain --tag $(TAG) --pull --no-cache . && \
	docker run --rm --volume=$$PWD:/mnt --user=$$UID:$(GID) $(TAG) sh -c 'cp /*.txt /mnt/'
