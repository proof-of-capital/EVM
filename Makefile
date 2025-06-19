# Makefile for ProofOfCapital contract deployment and management

# Default network (can be overridden)
NETWORK ?= sepolia

# Load environment variables
include .env
export

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

.PHONY: help build test deploy upgrade verify clean install

help: ## Display this help message
	@echo "$(BLUE)ProofOfCapital Contract Management$(NC)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install dependencies
	@echo "$(YELLOW)Installing dependencies...$(NC)"
	forge install
	@echo "$(GREEN)Dependencies installed successfully!$(NC)"

build: ## Build the contracts
	@echo "$(YELLOW)Building contracts...$(NC)"
	forge build
	@echo "$(GREEN)Build completed successfully!$(NC)"

test: ## Run tests
	@echo "$(YELLOW)Running tests...$(NC)"
	forge test -vvv
	@echo "$(GREEN)Tests completed!$(NC)"

test-coverage: ## Run tests with coverage
	@echo "$(YELLOW)Running tests with coverage...$(NC)"
	forge coverage
	@echo "$(GREEN)Coverage report generated!$(NC)"

deploy-dry-run: build ## Simulate deployment without broadcasting
	@echo "$(YELLOW)Simulating deployment to $(NETWORK)...$(NC)"
	@$(MAKE) _deploy-with-network NETWORK=$(NETWORK) DRY_RUN=true

deploy: build ## Deploy ProofOfCapital contract
	@echo "$(YELLOW)Deploying ProofOfCapital to $(NETWORK)...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(RED)Error: .env file not found. Please copy env.example to .env and configure it.$(NC)"; \
		exit 1; \
	fi
	@$(MAKE) _deploy-with-network NETWORK=$(NETWORK)

upgrade-dry-run: build ## Simulate upgrade without broadcasting
	@echo "$(YELLOW)Simulating upgrade on $(NETWORK)...$(NC)"
	@$(MAKE) _upgrade-with-network NETWORK=$(NETWORK) DRY_RUN=true

upgrade: build ## Upgrade ProofOfCapital contract
	@echo "$(YELLOW)Upgrading ProofOfCapital on $(NETWORK)...$(NC)"
	@$(MAKE) _upgrade-with-network NETWORK=$(NETWORK)

# Function to set network-specific variables
define set_network_vars
	$(eval NETWORK_RPC_URL := $(if $(filter mainnet,$(1)),$(RPC_URL_MAINNET),$(if $(filter sepolia,$(1)),$(RPC_URL_SEPOLIA),$(if $(filter polygon,$(1)),$(RPC_URL_POLYGON),))))
	$(eval NETWORK_API_KEY := $(if $(filter mainnet,$(1)),$(ETHERSCAN_API_KEY_MAINNET),$(if $(filter sepolia,$(1)),$(ETHERSCAN_API_KEY_SEPOLIA),$(if $(filter polygon,$(1)),$(POLYGONSCAN_API_KEY_POLYGON),))))
	$(eval NETWORK_WETH := $(if $(filter mainnet,$(1)),$(WETH_ADDRESS_MAINNET),$(if $(filter sepolia,$(1)),$(WETH_ADDRESS_SEPOLIA),$(if $(filter polygon,$(1)),$(WETH_ADDRESS_POLYGON),))))
	$(eval NETWORK_TOKEN_SUPPORT := $(if $(filter mainnet,$(1)),$(TOKEN_SUPPORT_ADDRESS_MAINNET),$(if $(filter sepolia,$(1)),$(TOKEN_SUPPORT_ADDRESS_SEPOLIA),$(if $(filter polygon,$(1)),$(TOKEN_SUPPORT_ADDRESS_POLYGON),))))
	$(eval NETWORK_PROXY := $(if $(filter mainnet,$(1)),$(PROXY_ADDRESS_MAINNET),$(if $(filter sepolia,$(1)),$(PROXY_ADDRESS_SEPOLIA),$(if $(filter polygon,$(1)),$(PROXY_ADDRESS_POLYGON),))))
endef

# Internal deployment function that uses pre-set network variables
_deploy-with-network:
	$(call set_network_vars,$(NETWORK))
	@if [ -z "$(NETWORK)" ] || [ "$(NETWORK)" != "mainnet" ] && [ "$(NETWORK)" != "sepolia" ] && [ "$(NETWORK)" != "polygon" ]; then \
		echo "$(RED)Error: Unsupported network $(NETWORK). Use: mainnet, sepolia, or polygon$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK_RPC_URL)" ]; then \
		echo "$(RED)Error: RPC_URL not set for $(NETWORK) network$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK_API_KEY)" ]; then \
		echo "$(RED)Error: API_KEY not set for $(NETWORK) network$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Network: $(NETWORK)$(NC)"
	@echo "$(BLUE)RPC URL: $(NETWORK_RPC_URL)$(NC)"
	@echo "$(BLUE)WETH Address: $(NETWORK_WETH)$(NC)"
	@if [ "$(DRY_RUN)" = "true" ]; then \
		WETH_ADDRESS=$(NETWORK_WETH) TOKEN_SUPPORT_ADDRESS=$(NETWORK_TOKEN_SUPPORT) \
		forge script script/DeployProofOfCapital.s.sol:DeployProofOfCapital \
			--rpc-url $(NETWORK_RPC_URL) \
			-vvvv; \
	else \
		WETH_ADDRESS=$(NETWORK_WETH) TOKEN_SUPPORT_ADDRESS=$(NETWORK_TOKEN_SUPPORT) \
		forge script script/DeployProofOfCapital.s.sol:DeployProofOfCapital \
			--rpc-url $(NETWORK_RPC_URL) \
			--broadcast \
			--verify \
			--etherscan-api-key $(NETWORK_API_KEY) \
			-vvvv; \
	fi

# Internal upgrade function that uses pre-set network variables
_upgrade-with-network:
	$(call set_network_vars,$(NETWORK))
	@if [ -z "$(NETWORK)" ] || [ "$(NETWORK)" != "mainnet" ] && [ "$(NETWORK)" != "sepolia" ] && [ "$(NETWORK)" != "polygon" ]; then \
		echo "$(RED)Error: Unsupported network $(NETWORK). Use: mainnet, sepolia, or polygon$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK_RPC_URL)" ]; then \
		echo "$(RED)Error: RPC_URL not set for $(NETWORK) network$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK_PROXY)" ]; then \
		echo "$(RED)Error: PROXY_ADDRESS not set for $(NETWORK) network$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Network: $(NETWORK)$(NC)"
	@echo "$(BLUE)RPC URL: $(NETWORK_RPC_URL)$(NC)"
	@echo "$(BLUE)Proxy Address: $(NETWORK_PROXY)$(NC)"
	@if [ "$(DRY_RUN)" = "true" ]; then \
		PROXY_ADDRESS=$(NETWORK_PROXY) \
		forge script script/UpgradeProofOfCapital.s.sol:UpgradeProofOfCapital \
			--rpc-url $(NETWORK_RPC_URL) \
			-vvvv; \
	else \
		PROXY_ADDRESS=$(NETWORK_PROXY) \
		forge script script/UpgradeProofOfCapital.s.sol:UpgradeProofOfCapital \
			--rpc-url $(NETWORK_RPC_URL) \
			--broadcast \
			--verify \
			--etherscan-api-key $(NETWORK_API_KEY) \
			-vvvv; \
	fi

verify: ## Verify contract on Etherscan
	$(call set_network_vars,$(NETWORK))
	@echo "$(YELLOW)Verifying contract...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NETWORK)" ] || [ "$(NETWORK)" != "mainnet" ] && [ "$(NETWORK)" != "sepolia" ] && [ "$(NETWORK)" != "polygon" ]; then \
		echo "$(RED)Error: Unsupported network $(NETWORK)$(NC)"; \
		exit 1; \
	fi
	@forge verify-contract $(CONTRACT_ADDRESS) src/ProofOfCapital.sol:ProofOfCapital \
		--chain-id $$(cast chain-id --rpc-url $(NETWORK_RPC_URL)) \
		--etherscan-api-key $(NETWORK_API_KEY)
	@echo "$(GREEN)Verification completed!$(NC)"

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	forge clean
	rm -f deployment-*.txt
	@echo "$(GREEN)Clean completed!$(NC)"

format: ## Format code
	@echo "$(YELLOW)Formatting code...$(NC)"
	forge fmt
	@echo "$(GREEN)Code formatted!$(NC)"

lint: ## Run linter
	@echo "$(YELLOW)Running linter...$(NC)"
	forge fmt --check
	@echo "$(GREEN)Linting completed!$(NC)"

gas-report: ## Generate gas usage report
	@echo "$(YELLOW)Generating gas report...$(NC)"
	forge test --gas-report
	@echo "$(GREEN)Gas report generated!$(NC)"

setup-env: ## Setup environment file from example
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Creating .env file from env.example...$(NC)"; \
		cp env.example .env; \
		echo "$(GREEN).env file created. Please edit it with your configuration.$(NC)"; \
	else \
		echo "$(YELLOW).env file already exists.$(NC)"; \
	fi

# Network-specific commands
deploy-mainnet: ## Deploy to mainnet
	@$(MAKE) deploy NETWORK=mainnet

deploy-sepolia: ## Deploy to sepolia
	@$(MAKE) deploy NETWORK=sepolia

deploy-polygon: ## Deploy to polygon
	@$(MAKE) deploy NETWORK=polygon

upgrade-mainnet: ## Upgrade on mainnet
	@$(MAKE) upgrade NETWORK=mainnet

upgrade-sepolia: ## Upgrade on sepolia
	@$(MAKE) upgrade NETWORK=sepolia

upgrade-polygon: ## Upgrade on polygon
	@$(MAKE) upgrade NETWORK=polygon

# Development helpers
dev-setup: install setup-env build test ## Complete development setup
	@echo "$(GREEN)Development environment setup completed!$(NC)"

check: build test lint ## Run all checks
	@echo "$(GREEN)All checks passed!$(NC)" 