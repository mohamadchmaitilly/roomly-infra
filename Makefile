# Terraform workflow for the infra repo.
#
# CONTRACT: the PR pipeline runs `make check` and nothing else for these checks.
# Add or change a check HERE, never as a separate CI step, so that a green local
# `make check` means a green PR. If the two ever diverge, this file is wrong.
#
# Usage: make <target> [ENV=staging]      (`make help` lists the targets)

SHELL := /bin/sh

ENV            ?= staging
TF_DIR         := envs/$(ENV)
TF             := terraform -chdir=$(TF_DIR)
PROJECT_PREFIX := roomly
PLAN           := tfplan
DESTROY_PLAN   := tfplan-destroy

.DEFAULT_GOAL := help

.PHONY: help init fmt validate lint security check plan apply output destroy

# Shell snippet used by plan/apply/destroy. This account is shared with parallel
# deployments, so before touching anything it reads what Terraform is ACTUALLY
# pointed at (the initialized backend in .terraform/, not backend.tf), prints it,
# and refuses if it does not look like this project's remote state.
define resolve_target
set -eu; \
state='$(TF_DIR)/.terraform/terraform.tfstate'; \
command -v jq >/dev/null || { echo 'ERROR: jq is required for the target guard.' >&2; exit 1; }; \
[ -f "$$state" ] || { echo "ERROR: no initialized backend in $(TF_DIR). Run 'make init' first." >&2; exit 1; }; \
btype=$$(jq -r '.backend.type // empty' "$$state"); \
bucket=$$(jq -r '.backend.config.bucket // empty' "$$state"); \
key=$$(jq -r '.backend.config.key // empty' "$$state"); \
region=$$(jq -r '.backend.config.region // empty' "$$state"); \
[ "$$btype" = s3 ] || { echo "ERROR: backend type is '$$btype', expected s3. Refusing." >&2; exit 1; }; \
[ -n "$$bucket" ] && [ -n "$$key" ] || { echo 'ERROR: backend bucket or key is missing. Refusing.' >&2; exit 1; }; \
prefix=$$(printf 'var.name_prefix\n' | $(TF) console | tr -d '"'); \
[ "$$prefix" = '$(PROJECT_PREFIX)' ] || { echo "ERROR: name_prefix is '$$prefix', this project uses '$(PROJECT_PREFIX)'. Refusing." >&2; exit 1; }; \
echo; \
echo '  Target of this command'; \
echo "    environment : $(ENV)  ($(TF_DIR))"; \
echo "    state bucket: $$bucket"; \
echo "    state key   : $$key"; \
echo "    region      : $$region"; \
echo "    name_prefix : $$prefix"; \
echo
endef

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

init: ## terraform init (plus tflint plugins)
	$(TF) init
	tflint --init

fmt: ## terraform fmt -recursive
	terraform fmt -recursive

validate: ## fmt -check + terraform validate (needs no AWS credentials)
	terraform fmt -check -recursive
	$(TF) init -backend=false -input=false
	$(TF) validate

lint: ## tflint across the root, modules and envs
	tflint --init
	tflint --recursive --config=$(CURDIR)/.tflint.hcl

security: ## checkov + trivy config
	checkov --config-file .checkov.yaml
	trivy config --exit-code 1 --severity HIGH,CRITICAL --skip-dirs .terraform .

check: validate lint security ## validate + lint + security (exactly what the PR pipeline runs)

plan: ## show the target, then terraform plan (saved to a plan file)
	@$(resolve_target)
	$(TF) plan -input=false -out=$(PLAN)

apply: ## show the target, plan, ask y/N, apply exactly that plan
	@$(resolve_target)
	$(TF) plan -input=false -out=$(PLAN)
	@printf 'Apply the plan above? [y/N] '; read answer; \
	if [ "$$answer" = y ]; then :; else rm -f $(TF_DIR)/$(PLAN); echo 'Aborted.'; exit 1; fi
	$(TF) apply -input=false $(PLAN)
	@rm -f $(TF_DIR)/$(PLAN)

output: ## terraform output
	$(TF) output

destroy: ## DESTROY ENV: prints bucket/key/name_prefix, typed confirmation, never touches the state bucket
	@$(resolve_target); \
	trap 'rm -f "$(TF_DIR)/$(DESTROY_PLAN)"' EXIT; \
	$(TF) plan -destroy -input=false -out=$(DESTROY_PLAN); \
	$(TF) show -json $(DESTROY_PLAN) | jq -e --arg b "$$bucket" \
	  '[.resource_changes[]? | select(.change.actions | index("delete")) | select((.change.before.bucket? // "") == $$b or (.change.before.id? // "") == $$b)] | length == 0' >/dev/null \
	  || { echo "ERROR: the destroy plan would delete the Terraform state bucket '$$bucket'. Refusing." >&2; exit 1; }; \
	echo; \
	printf 'This will DESTROY the resources listed above. Type the name_prefix shown above to continue: '; \
	read answer; \
	[ "$$answer" = "$$prefix" ] || { echo 'Confirmation did not match. Nothing was destroyed.' >&2; exit 1; }; \
	$(TF) apply -input=false $(DESTROY_PLAN)