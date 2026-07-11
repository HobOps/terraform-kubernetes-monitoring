SHELL:=bash

REQUIRED_BINS := terraform
$(foreach bin,$(REQUIRED_BINS),\
    $(if $(shell command -v $(bin) 2> /dev/null),$(info Found `$(bin)`),$(error Please install `$(bin)`)))

help:
	@echo ======= Available commands =======
	@grep '^[a-z0-9].*:' Makefile | sed 's/://g'

.DEFAULT_GOAL := help

ENCRYPTION_KEY_PATH ?= ./encryption_key.txt

init:
	@export SECRET_KEY=$$(sops -d $(ENCRYPTION_KEY_PATH) 2>/dev/null || true); \
	if [ -n "$$SECRET_KEY" ]; then \
	  terraform init -backend-config="encryption_key=$$SECRET_KEY"; \
	else \
	  terraform init; \
	fi

clean:
	@rm -rf .terraform
