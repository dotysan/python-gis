SHELL:=/usr/bin/env bash

TAG:=$(notdir $(CURDIR))
PYVER:=$(shell grep -oP 'ARG PYVER=\K.*' Dockerfile)
GDVER:=$(shell grep -oP 'ARG GDVER=\K.*' Dockerfile)
REL=$(TAG):$(PYVER)-gdal$(GDVER)
GID=$(shell id -g)

.PHONY: run bash push push-docker push-github tag build force ls rm

run: build
	docker run --rm -it $(TAG):latest
bash: build
	docker run --rm -it $(TAG):latest bash

push: push-docker push-github

push-docker: build tag
	DOCKER_HUBUSER=$$(jq --raw-output '.auths["https://index.docker.io/v1/"].auth' \
		~/.docker/config.json |base64 --decode |cut -d: -f1); \
	if [[ -z "$$DOCKER_HUBUSER" ]]; then \
		read -p "Enter your Docker Hub username: " DOCKER_HUBUSER; \
		if [[ -z "$$DOCKER_HUBUSER" ]]; then \
			echo "ERROR: Docker Hub username not provided. Exiting." >&2; \
			exit 1; \
		fi; \
		docker login --username $$DOCKER_HUBUSER; \
	fi; \
	docker tag $(TAG):latest $$DOCKER_HUBUSER/$(TAG):latest; \
	docker tag $(REL) $$DOCKER_HUBUSER/$(REL); \
	docker push $$DOCKER_HUBUSER/$(TAG):latest; \
	docker push $$DOCKER_HUBUSER/$(REL)

push-github: build tag
	DOCKER_GHUSER=$$(jq --raw-output '.auths["ghcr.io"].auth' \
		~/.docker/config.json |base64 --decode |cut -d: -f1); \
	if [[ -z "$$DOCKER_GHUSER" ]]; then \
		if [[ -z "$$GITHUB_TOKEN" ]]; then \
			echo "ERROR: Missing GITHUB_TOKEN in environment. Please set it or log in manually." >&2; \
			exit 1; \
		fi; \
		GH_USERID=$$(gh api user --jq .login); \
		if [[ -z "$$GH_USERID" ]]; then \
			echo "ERROR: Unable to retrieve GitHub username using 'gh' CLI. Ensure 'gh auth login' is completed." >&2; \
			exit 1; \
		fi; \
		echo "$GITHUB_TOKEN" |docker login --username "$$GH_USERID" --password-stdin ghcr.io; \
		DOCKER_GHUSER="$$GH_USERID"; \
	fi; \
	docker tag $(TAG):latest ghcr.io/$$DOCKER_GHUSER/$(TAG):latest; \
	docker tag $(REL) ghcr.io/$$DOCKER_GHUSER/$(REL); \
	docker push ghcr.io/$$DOCKER_GHUSER/$(TAG):latest; \
	docker push ghcr.io/$$DOCKER_GHUSER/$(REL)

tag: build
	docker tag $(TAG):latest $(REL)

image_exists = $(shell docker image inspect $(TAG):latest --format="exists" 2>/dev/null || echo "")
last_built = $(shell docker image inspect $(TAG):latest --format='{{.Created}}' 2>/dev/null | cut -d'.' -f1)

build:
ifeq ($(image_exists),)
	docker build --progress=plain --tag $(TAG):latest . && \
	  docker run --rm --volume=$$PWD:/mnt --user=$$UID:$(GID) $(TAG):latest sh -c 'cp /*.txt /mnt/'
else
	@echo "Not rebuilding $(TAG):latest built $(last_built). If you don't like that, try \`make rm\` to remove it first."
endif
force:
	docker build --progress=plain --tag $(TAG):latest --pull --no-cache . && \
	  docker run --rm --volume=$$PWD:/mnt --user=$$UID:$(GID) $(TAG):latest sh -c 'cp /*.txt /mnt/'

ls:
	@docker image ls |grep --color=always -E "$(TAG)|^REPO"

rm:
	docker image rm $(TAG):latest
