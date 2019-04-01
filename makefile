# Initial variables
os ?= $(shell uname -s)

ifeq ($(os), Darwin)
open = open
else ifeq ($(shell uname), Linux)
open = xdg-open
else ifeq ($(shell uname), Windows_NT)
open =  explorer
endif

build: recreate ?= 
build:
	docker-compose up -d --build --remove-orphans $(recreate) $(container)

remove: ## Remove containers
	docker-compose rm --force --stop $(container)

reload up: ## Reload one or all containers 
	docker-compose up -d $(container)

down: 
	docker-compose down $(container)

stop:
	docker-compose stop $(container)

start:
	docker-compose start $(container)

restart:
	docker-compose restart $(container)

rebuild: | down build ## Rebuild containers

reboot: | remove up ## Recreate containers

status ps:
	docker-compose ps $(container)

cli exec: container ?= app
cli exec: bash ?= ash
cli exec: ## Execute commands in containers, use "command"  argument to send the command. By Default enter the shell.
	docker-compose exec $(container) $(bash) $(command)

run: container ?= app
run: bash ?= ash
run: ## Run commands in a new container
	docker-compose run --rm $(container) $(bash) $(command)

config:
	docker-compose config

logs: container ?= app
logs: ## Show logs. Usage: make logs [container=app]
	docker-compose logs -f $(container)

copy: container ?= app
copy: ## Copy app files/directories from container to host
	docker cp $(shell docker-compose ps -q $(container)):$(path) .

open: ## Open app in the browser
	$(open) $(subst 0.0.0.0,localhost,http://$(shell docker-compose port app 8080))/greeting

expose: ## Expose your local environment to the internet, thanks to Serveo (https://serveo.net)
	ssh -R 80:localhost:$(subst 0.0.0.0:,,$(shell docker-compose port app 8080)) serveo.net

# Update Docker Image in ECR
tag: ## Tag and push current branch. Usage make tag version=<semver>
	git tag -a $(version) -m "Version $(version)"
	git push origin $(version)

squash: branch := $(shell git rev-parse --abbrev-ref HEAD)
squash:
	git rebase -i $(shell git merge-base origin/$(branch) origin/master)
	git push -f

publish: container ?= app
publish: environment ?= Production
#publish: test release checkoutlatesttag deployimage
publish: ## Tag and deploy version. Registry authentication required. Usage: make publish
	make updateservice

preview review: container ?= app
preview review: version := $(shell git rev-parse --abbrev-ref HEAD)
preview review: | build
	make deployimage
	make updateservice

push: branch := $(shell git rev-parse --abbrev-ref HEAD)
push: ## Review, add, commit and push changes using commitizen. Usage: make push
	git diff
	git add -A .
	@docker run --rm -it -e CUSTOM=true -v $(CURDIR):/app -v $(HOME)/.gitconfig:/root/.gitconfig aplyca/commitizen
	git pull origin $(branch)
	git push -u origin $(branch)

checkoutlatesttag:
	git fetch --prune origin "+refs/tags/*:refs/tags/*"
	git checkout $(shell git describe --always --abbrev=0 --tags)

ecslogin:
	$(shell docker run --rm -it --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} --env AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} infrastructureascode/aws-cli:1.16.23 ash -c "aws ecr get-login --no-include-email --region us-east-2")

release:
	git checkout production
	docker run --rm -it -v $(CURDIR):/app -v ~/.ssh:/root/.ssh -w /app aplyca/semantic-release ash -c "semantic-release --no-ci"
	git pull

updateservice: environment ?= prod
updateservice: ## �  Update service in ECS: customAppService
	$(info �  Updating ECS service SpringBoot APP ...)
	@docker run --rm -it --env AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} --env AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} infrastructureascode/aws-cli ash -c "aws ecs update-service --cluster customApp --service customAppService --force-new-deployment --region us-east-2 --query 'service.{status:status,pendingCount:pendingCount,desiredCount:desiredCount,runningCount:runningCount,serviceName:serviceName,taskDefinition:taskDefinition}'"

deployimage: container ?= app
deployimage: registryurl ?= 111377159952.dkr.ecr.us-east-2.amazonaws.com/springboot/app
deployimage: version ?= $(shell git describe --always --abbrev=0 --tags)
deployimage: ecslogin ## �  Login to Registry, build, tag and push the images. Registry authentication required. Usage: make deployimage version="<semver>". Use version=latest to create the
	latest image
		$(info �  Pushing version '$(version)' of the '$(container)' Docker image ...)
		docker build --target prod -t $(registryurl):$(version) -f Dockerfile .
		docker push $(registryurl):$(version)

#deploylatestimage: version ?= $(shell git describe --always --abbrev=0 --tags)
deploylatestimage: version ?= latest
deploylatestimage: ## Login to Registry, build, tag with the latest images and push to registry. Registry authentication required. Usage: make deploylatestimage version="<semver>"
	docker tag $(registryurl):$(version) $(registryurl):latest
	docker push $(registryurl):latest

h help: ## This help.
	@echo 'Usage: make <task>'
	@echo 'Default task: build'
	@echo
	@echo 'Tasks:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9., _-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := build
.PHONY: all	