DOCKER          = docker
DOCKER_COMPOSE  = docker-compose
PHP_SERVICE     = $(DOCKER_COMPOSE) exec php-fpm sh -c
UID             = $(shell id -u)
BUILDER         = $(shell docker-compose config --services | xargs)

##
## ----------------------------------------------------------------------------
##   Environment
## ----------------------------------------------------------------------------
##

build: ## Build the environment
	$(DOCKER_COMPOSE) build --build-arg unix_ID=$(UID) $(BUILDER)

config: ## Generate the ".env" file if it doesn't already exist
	-@test -f .env || cp .env.dist .env
	-@test -f docker/xdebug.env || cp docker/xdebug.env.dist docker/xdebug.env
	-@test -f phpspec.yml || cp phpspec.yml.dist phpspec.yml
	-@test -f phpstan.neon || cp phpstan.neon.dist phpstan.neon
	-@test -f .php_cs || cp .php_cs.dist .php_cs
	-@test -f .php_cs.spec || cp .php_cs.spec.dist .php_cs.spec

install: ## Install the environment
	make config stop uninstall build start composer
	@make reset
	make assets
	@printf "\033[32m✓ Installation done\n"

assets:
	$(PHP_SERVICE) "bin/console_dist assets:install"

logs: ## Follow logs generated by all containers
	$(DOCKER_COMPOSE) logs -f --tail=0

logs-full: ## Follow logs generated by all containers from the containers creation
	$(DOCKER_COMPOSE) logs -f

ps: ## List all containers managed by the environment
	$(DOCKER_COMPOSE) ps

restart: ## Restart the environment
	$(DOCKER_COMPOSE) restart

start: ## Start the environment
	$(DOCKER_COMPOSE) up -d --remove-orphans

stats: ## Print real-time statistics about containers ressources usage
	$(DOCKER) stats $($(DOCKER) ps --format={{.Names}})

stop: ## Stop the environment
	$(DOCKER_COMPOSE) stop

uninstall: ## Uninstall the environment
	make config
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) down --volumes --remove-orphans
	@printf "\033[32m✓ Uninstallation done\n"

.PHONY: build config install assets logs logs-full ps restart start stats stop uninstall


##
## ----------------------------------------------------------------------------
##   Project
## ----------------------------------------------------------------------------
##

cc: ## Clears the cache
	$(PHP_SERVICE) "/bin/rm -rf var/cache/*/ var/logs/*/"

composer: ## Install Composer dependencies from the "php" container
	$(PHP_SERVICE) "composer install --optimize-autoloader || true"

webserver: ## Open a terminal in the "webserver" container
	$(DOCKER_COMPOSE) exec webserver sh

php: ## Open a terminal in the "php" container
	$(DOCKER_COMPOSE) exec php-fpm sh

reset: ## Reset the database used by the specified environment
	$(PHP_SERVICE) "bin/console_dist doctrine:database:drop --if-exists --force && \
		bin/console_dist doctrine:database:create --if-not-exists && \
		bin/console_dist doctrine:schema:create --no-interaction"

.PHONY: composer apache php reset

##
## ----------------------------------------------------------------------------
##   Quality
## ----------------------------------------------------------------------------
##

check: ## Execute all quality assurance tools
	make lint phpcsfixer security

lint: ## Lint YAML configuration
	$(PHP_SERVICE) "php bin/console_dist lint:yaml config"

phpcsfixer: ## Run the PHP coding standards fixer on dry-run mode
	@test -f .php_cs || cp .php_cs.dist .php_cs
	$(PHP_SERVICE) "php vendor/bin/php-cs-fixer fix --config=.php_cs \
		--verbose --dry-run" && \
	$(PHP_SERVICE) "php vendor/bin/php-cs-fixer fix --config=.php_cs.spec \
		--verbose --dry-run"

phpcsfixer-apply: ## Run the PHP coding standards fixer on apply mode
	@test -f .php_cs || cp .php_cs.dist .php_cs && \
	$(PHP_SERVICE) "php vendor/bin/php-cs-fixer fix --config=.php_cs \
		--verbose" && \
	$(PHP_SERVICE) "php vendor/bin/php-cs-fixer fix --config=.php_cs.spec \
		--verbose"

tests: SHELL := /bin/bash
tests:
	@./git-hooks/pre-commit

security: ## Run a security analysis on dependencies
	$(PHP_SERVICE) "php bin/console_dist security:check"

.PHONY: check lint phpcsfixer phpcsfixer-apply phpunit security

.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' \
		| sed -e 's/\[32m##/[33m/'
.PHONY: help
