# Docsrv: configure the languages whose api-doc can be auto generated
LANGUAGES = "go scala python"
# Docsrv: configure the directory containing the python sources
PYTHON_MAIN_DIR ?= ./python
# Docs: do not edit this
DOCS_REPOSITORY := https://github.com/src-d/docs
SHARED_PATH ?= $(shell pwd)/.docsrv-resources
DOCS_PATH ?= $(SHARED_PATH)/.docs
$(DOCS_PATH)/Makefile.inc:
	git clone --quiet --depth 1 $(DOCS_REPOSITORY) $(DOCS_PATH);
-include $(DOCS_PATH)/Makefile.inc

# Docker
DOCKER_CMD = docker
DOCKER_BUILD = $(DOCKER_CMD) build
DOCKER_TAG ?= $(DOCKER_CMD) tag
DOCKER_PUSH ?= $(DOCKER_CMD) push
DOCKER_RUN = $(DOCKER_CMD) run
DOCKER_RMI = $(DOCKER_CMD) rmi -f
DOCKER_EXEC = $(DOCKER_CMD) exec

# Docker run bblfsh server container
BBLFSH_CONTAINER_NAME = bblfshd
BBLFSH_HOST_PORT = 9432
BBLFSH_CONTAINER_PORT = 9432
BBLFSH_HOST_VOLUME = /var/lib/bblfshd
BBLFSH_CONTAINER_VOLUME = /var/lib/bblfshd
BBLFSH_IMAGE = bblfsh/bblfshd
BBLFSH_VERSION = v2.5.0

BBLFSH_RUN_FLAGS := --detach --name $(BBLFSH_CONTAINER_NAME) --privileged \
	-p $(BBLFSH_HOST_PORT):$(BBLFSH_CONTAINER_PORT) \
	-v $(BBLFSH_HOST_VOLUME):$(BBLFSH_CONTAINER_VOLUME) \
	$(BBLFSH_IMAGE):$(BBLFSH_VERSION)

BBLFSH_EXEC_FLAGS = -it
BBLFSH_CTL = bblfshctl
BBLFSH_CTL_DRIVER := $(BBLFSH_CTL) driver

BBLFSH_CTL_LIST_DRIVERS := $(BBLFSH_CTL_DRIVER) list
BBLFSH_EXEC_LIST_COMMAND := $(BBLFSH_CONTAINER_NAME) bblfshctl driver list
BBLFSH_LIST_DRIVERS := $(BBLFSH_EXEC_FLAGS) $(BBLFSH_EXEC_LIST_COMMAND)


# escape_docker_tag escape colon char to allow use a docker tag as rule
define escape_docker_tag
$(subst :,--,$(1))
endef

# unescape_docker_tag an escaped docker tag to be use in a docker command
define unescape_docker_tag
$(subst --,:,$(1))
endef

# Docker jupyter image tag
GIT_COMMIT=$(shell git rev-parse HEAD | cut -c1-7)
GIT_DIRTY=
ifneq ($(shell git status --porcelain), )
	GIT_DIRTY := -dirty
endif
DEV_PREFIX := dev
VERSION ?= $(DEV_PREFIX)-$(GIT_COMMIT)$(GIT_DIRTY)

# Docker jupyter image
JUPYTER_IMAGE ?= srcd/engine-jupyter
JUPYTER_IMAGE_VERSIONED ?= $(call escape_docker_tag,$(JUPYTER_IMAGE):$(VERSION))

# Docker run jupyter container
JUPYTER_CONTAINER_NAME = engine-jupyter
JUPYTER_HOST_PORT = 8080
JUPYTER_CONTAINER_PORT = 8080
REPOSITORIES_HOST_DIR := $(PWD)/_examples/siva-files
REPOSITORIES_CONTAINER_DIR = /repositories
JUPYTER_RUN_FLAGS := --name $(JUPYTER_CONTAINER_NAME) --rm -it \
	-p $(JUPYTER_HOST_PORT):$(JUPYTER_CONTAINER_PORT) \
	-v $(REPOSITORIES_HOST_DIR):$(REPOSITORIES_CONTAINER_DIR) \
	--link $(BBLFSH_CONTAINER_NAME):$(BBLFSH_CONTAINER_NAME) \
	$(call unescape_docker_tag,$(JUPYTER_IMAGE_VERSIONED))

# Versions
SCALA_VERSION ?= 2.11.11
SPARK_VERSION ?= 2.2.1

# if TRAVIS_SCALA_VERSION defined SCALA_VERSION is overrided
ifneq ($(TRAVIS_SCALA_VERSION), )
	SCALA_VERSION := $(TRAVIS_SCALA_VERSION)
endif

# if TRAVIS_TAG defined VERSION is overrided
ifneq ($(TRAVIS_TAG), )
	VERSION := $(TRAVIS_TAG)
endif

# if we are not in master, and it's not a tag the push is disabled
ifneq ($(TRAVIS_BRANCH), master)
	ifeq ($(TRAVIS_TAG), )
        pushdisabled = "push disabled for non-master branches"
	endif
endif

# if this is a pull request, the push is disabled
ifneq ($(TRAVIS_PULL_REQUEST), false)
        pushdisabled = "push disabled for pull-requests"
endif

#SBT
SBT = ./sbt ++$(SCALA_VERSION) -Dspark.version=$(SPARK_VERSION)

# Rules
all: clean build

clean:
	$(SBT) clean

test:
	$(SBT) test

build:
	$(SBT) assembly

travis-test:
	$(SBT) clean coverage test coverageReport scalastyle test:scalastyle

docker-bblfsh:
	$(DOCKER_RUN) $(BBLFSH_RUN_FLAGS)

docker-bblfsh-install-drivers:
	$(DOCKER_EXEC) $(BBLFSH_CONTAINER_NAME) bblfshctl driver install go bblfsh/go-driver:v0.4.0
	$(DOCKER_EXEC) $(BBLFSH_CONTAINER_NAME) bblfshctl driver install python bblfsh/python-driver:v2.0.0
	$(DOCKER_EXEC) $(BBLFSH_CONTAINER_NAME) bblfshctl driver install java bblfsh/java-driver:v1.2.6
	$(DOCKER_EXEC) $(BBLFSH_CONTAINER_NAME) bblfshctl driver install ruby bblfsh/ruby-driver:v2.0.0

docker-bblfsh-list-drivers:
	$(DOCKER_EXEC) $(BBLFSH_LIST_DRIVERS)

docker-build:
	$(if $(pushdisabled),$(error $(pushdisabled)))

	$(DOCKER_BUILD) -t $(call unescape_docker_tag,$(JUPYTER_IMAGE_VERSIONED)) .

docker-run:
	$(DOCKER_RUN) $(JUPYTER_RUN_FLAGS)

docker-clean:
	$(DOCKER_RMI) $(call unescape_docker_tag,$(JUPYTER_IMAGE_VERSIONED))

docker-push: docker-build
	$(if $(pushdisabled),$(error $(pushdisabled)))

	@if [ "$$DOCKER_USERNAME" != "" ]; then \
		$(DOCKER_CMD) login -u="$$DOCKER_USERNAME" -p="$$DOCKER_PASSWORD"; \
	fi;

	$(DOCKER_PUSH) $(call unescape_docker_tag,$(JUPYTER_IMAGE_VERSIONED))
	@if [ "$$TRAVIS_TAG" != "" ]; then \
		$(DOCKER_TAG) $(call unescape_docker_tag,$(JUPYTER_IMAGE_VERSIONED)) \
			$(call unescape_docker_tag,$(JUPYTER_IMAGE)):latest; \
		$(DOCKER_PUSH) $(call unescape_docker_tag,$(JUPYTER_IMAGE):latest); \
	fi;

maven-release:
	$(SBT) clean publishSigned && \
	$(SBT) sonatypeRelease
