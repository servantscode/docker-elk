## import config.
## You can change the default config with `make cnf="config_special.env" build`
#cnf ?= config.env
#include $(cnf)
#export $(shell sed 's/=.*//' $(cnf))
#
## import deploy config
## You can change the default deploy config with `make cnf="deploy_special.env" release`
#dpl ?= deploy.env
#include $(dpl)
#export $(shell sed 's/=.*//' $(dpl))

# grep the version from the mix file
VERSION=$(shell cat version.txt)

LATEST=$(shell kubectl.exe describe deployment kibana | grep Image | grep latest)
ifeq ($(LATEST),)
TAG=:latest
else
TAG=
endif

# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help build

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help


# DOCKER TASKS
# Build the container
build: ## Build the container
	cd elasticsearch; docker.exe build -t docker-elk_elasticsearch --build-arg ELK_VERSION=$(VERSION) .
	cd logstash; docker.exe build -t docker-elk_logstash --build-arg ELK_VERSION=$(VERSION) .
	cd kibana; docker.exe build -t docker-elk_kibana --build-arg ELK_VERSION=$(VERSION) .

run: ## Run container on port configured in `config.env`
	kubectl.exe create -f elasticsearch/kube.yml
	kubectl.exe create configmap logstash-config --from-file logstash/config/logstash.yml
	kubectl.exe create configmap pipeline-config --from-file logstash/pipeline/logstash.conf
	kubectl.exe create -f logstash/kube.yml 
	kubectl.exe create configmap kibana-config --from-file kibana/config/kibana.yml
	kubectl.exe create -f kibana/kube.yml

up: build run ## Run container on port configured in `config.env` (Alias to run)

update:
	kubectl.exe set image statefulset/elasticsearch elasticsearch=docker-elk_elasticsearch$(TAG)
	kubectl.exe set image deployment/logstash logstash=docker-elk_logstash$(TAG)
	kubectl.exe set image deployment/kibana kibana=docker-elk_kibana$(TAG)

stop: ## Stop and remove a running container
	kubectl.exe delete -f kibana/kube.yml
	kubectl.exe delete configmap kibana-config
	kubectl.exe delete -f logstash/kube.yml 
	kubectl.exe delete configmap logstash-config
	kubectl.exe delete configmap pipeline-config
	kubectl.exe delete -f elasticsearch/kube.yml
	kubectl.exe delete pvc data-elasticsearch-0 data-elasticsearch-1

#release: build-nc publish ## Make a release by building and publishing the `{version}` ans `latest` tagged containers to ECR

# Docker publish
# publish: repo-login publish-latest publish-version ## Publish the `{version}` ans `latest` tagged containers to ECR
publish: publish-latest publish-version ## Publish the `{version}` ans `latest` tagged containers to ECR

publish-latest: tag-latest ## Publish the `latest` taged container to ECR
	@echo 'publish latest to $(DOCKER_REPO)'
	docker.exe push $(DOCKER_REPO)/servantscode/$(APP_NAME):latest

publish-version: tag-version ## Publish the `{version}` taged container to ECR
	@echo 'publish $(VERSION) to $(DOCKER_REPO)'
	docker.exe push $(DOCKER_REPO)/servantscode/$(APP_NAME):$(VERSION)

# Docker tagging
tag: tag-latest tag-version ## Generate container tags for the `{version}` ans `latest` tags

tag-latest: ## Generate container `{version}` tag
	@echo 'create tag latest'
	docker.exe tag servantscode/$(APP_NAME) $(DOCKER_REPO)/servantscode/$(APP_NAME):latest

tag-version: ## Generate container `latest` tag
	@echo 'create tag $(VERSION)'
	docker.exe tag servantscode/$(APP_NAME) $(DOCKER_REPO)/servantscode/$(APP_NAME):$(VERSION)

logs: ## Get logs from running container
	kubectl.exe logs $(shell kubectl.exe get pods | grep $(APP_NAME) | grep Running | cut -d ' ' -f 1)

# HELPERS

# generate script to login to aws docker repo
CMD_REPOLOGIN := "eval $$\( aws ecr"
ifdef AWS_CLI_PROFILE
CMD_REPOLOGIN += " --profile $(AWS_CLI_PROFILE)"
endif
ifdef AWS_CLI_REGION
CMD_REPOLOGIN += " --region $(AWS_CLI_REGION)"
endif
CMD_REPOLOGIN += " get-login --no-include-email \)"

# login to AWS-ECR
repo-login: ## Auto login to AWS-ECR unsing aws-cli
	@eval $(CMD_REPOLOGIN)

version: ## Output the current version
	@echo $(VERSION)
