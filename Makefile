SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

TF_DIR      := infra/terraform
ANSIBLE_DIR := infra/ansible
K8S_DIR     := deploy/k8s
PROFILE     ?= tethys
REGION      ?= us-east-1

export AWS_PROFILE=$(PROFILE)
export AWS_REGION=$(REGION)

## help: list targets
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed -E 's/## ?//' | column -t -s ':'

# --------------------------------------------------------------------------
# Infrastructure
# --------------------------------------------------------------------------

## init: terraform init
init:
	cd $(TF_DIR) && terraform init

## plan: terraform plan
plan:
	cd $(TF_DIR) && terraform plan

## apply: terraform apply
apply:
	cd $(TF_DIR) && terraform apply

## destroy: terraform destroy (prompts for confirmation)
destroy:
	cd $(TF_DIR) && terraform destroy

## fmt: terraform fmt
fmt:
	cd $(TF_DIR) && terraform fmt -recursive

## validate: terraform validate
validate:
	cd $(TF_DIR) && terraform validate

## output: print terraform outputs
output:
	cd $(TF_DIR) && terraform output

# --------------------------------------------------------------------------
# Configuration management
# --------------------------------------------------------------------------

## ansible-ping: ensure all inventory hosts reachable
ansible-ping:
	cd $(ANSIBLE_DIR) && ansible all -i inventory.ini -m ping

## configure: run full site playbook (hardening + K3s + Jenkins)
configure:
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.ini playbooks/site.yml

## harden: run only CIS-lite hardening
harden:
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.ini playbooks/harden.yml

# --------------------------------------------------------------------------
# Kubernetes
# --------------------------------------------------------------------------

## deploy: apply all K8s manifests
deploy:
	kubectl apply -f $(K8S_DIR)/namespace.yaml
	kubectl apply -R -f $(K8S_DIR)/policies
	kubectl apply -R -f $(K8S_DIR)/vault
	kubectl apply -R -f $(K8S_DIR)/wiper
	kubectl apply -R -f $(K8S_DIR)/frontend
	kubectl apply -R -f $(K8S_DIR)/ingress

## undeploy: delete K8s resources (keeps the namespace)
undeploy:
	kubectl delete -R -f $(K8S_DIR)/ingress || true
	kubectl delete -R -f $(K8S_DIR)/frontend || true
	kubectl delete -R -f $(K8S_DIR)/wiper || true
	kubectl delete -R -f $(K8S_DIR)/vault || true

## rollout: wait for all Deployments to become ready
rollout:
	kubectl -n tethys rollout status deploy/vault
	kubectl -n tethys rollout status deploy/frontend

# --------------------------------------------------------------------------
# Services
# --------------------------------------------------------------------------

## build-images: build all service Docker images
build-images:
	docker build -t tethys/vault:dev    services/vault
	docker build -t tethys/wiper:dev    services/wiper
	docker build -t tethys/frontend:dev services/frontend

## test: run unit tests for every service
test:
	cd services/vault    && go test ./...
	cd services/wiper    && go test ./...
	cd services/frontend && npm test --silent

# --------------------------------------------------------------------------
# Cost helpers
# --------------------------------------------------------------------------

## stop-ec2: stop all tethys-tagged EC2 instances (saves free-tier hours)
stop-ec2:
	ids=$$(aws ec2 describe-instances \
	    --filters Name=tag:Project,Values=tethys Name=instance-state-name,Values=running \
	    --query 'Reservations[].Instances[].InstanceId' --output text); \
	[ -n "$$ids" ] && aws ec2 stop-instances --instance-ids $$ids || echo "no running instances"

## start-ec2: start previously stopped tethys instances
start-ec2:
	ids=$$(aws ec2 describe-instances \
	    --filters Name=tag:Project,Values=tethys Name=instance-state-name,Values=stopped \
	    --query 'Reservations[].Instances[].InstanceId' --output text); \
	[ -n "$$ids" ] && aws ec2 start-instances --instance-ids $$ids || echo "no stopped instances"

.PHONY: help init plan apply destroy fmt validate output \
        ansible-ping configure harden \
        deploy undeploy rollout \
        build-images test \
        stop-ec2 start-ec2
