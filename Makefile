# Makefile for ProofOfCapital contract deployment and management

.PHONY: all build test clean install format lint gas-report test-coverage setup-env check dev-setup help
.PHONY: deploy deploy-local deploy-sepolia deploy-mainnet deploy-polygon deploy-bsc
.PHONY: deploy-dry-run deploy-dry-run-local deploy-dry-run-sepolia deploy-dry-run-mainnet deploy-dry-run-polygon deploy-dry-run-bsc
.PHONY: verify verify-sepolia verify-mainnet verify-polygon verify-bsc

include .env

LOCAL_RPC_URL := http://127.0.0.1:8545

SEPOLIA_RPC := ${RPC_URL_SEPOLIA}
MAINNET_RPC := ${RPC_URL_MAINNET}
POLYGON_RPC := ${RPC_URL_POLYGON}
BSC_RPC := ${RPC_URL_BSC}

DEPLOY_SCRIPT := script/DeployProofOfCapital.s.sol:DeployProofOfCapital

PRIVATE_KEY := ${PRIVATE_KEY}

all: help

install:
	@echo "Installing dependencies..."
	forge install
	@echo "Dependencies installed successfully!"

build:
	@echo "Building contracts..."
	forge build
	@echo "Build completed successfully!"

test:
	@echo "Running tests..."
	forge test -vvv
	@echo "Tests completed!"

test-coverage:
	@echo "Running tests with coverage..."
	forge coverage
	@echo "Coverage report generated!"

clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -f deployment-*.txt
	@echo "Clean completed!"

format:
	@echo "Formatting code..."
	forge fmt
	@echo "Code formatted!"

lint:
	@echo "Running linter..."
	forge fmt --check
	@echo "Linting completed!"

gas-report:
	@echo "Generating gas report..."
	forge test --gas-report
	@echo "Gas report generated!"

setup-env:
	@if [ ! -f .env ]; then \
		echo "Creating .env file from env.example..."; \
		cp env.example .env; \
		echo ".env file created. Please edit it with your configuration."; \
	else \
		echo ".env file already exists."; \
	fi

# Deploy commands
deploy-local:
	forge clean
	@echo "Deploying ProofOfCapital to local network..."
	WETH_ADDRESS=${WETH_ADDRESS_SEPOLIA} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_SEPOLIA} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

deploy-sepolia:
	forge clean
	@echo "Deploying ProofOfCapital to Sepolia test network..."
	WETH_ADDRESS=${WETH_ADDRESS_SEPOLIA} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_SEPOLIA} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-mainnet:
	forge clean
	@echo "Deploying ProofOfCapital to Mainnet..."
	WETH_ADDRESS=${WETH_ADDRESS_MAINNET} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_MAINNET} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

deploy-polygon:
	forge clean
	@echo "Deploying ProofOfCapital to Polygon network..."
	WETH_ADDRESS=${WETH_ADDRESS_POLYGON} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_POLYGON} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ETHERSCAN_API_KEY} \
		--verifier etherscan \
		--legacy \
		-vvv

deploy-bsc:
	forge clean
	@echo "Deploying ProofOfCapital to BSC network..."
	TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_BSC} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BSCSCAN_API_KEY} \
		--verifier etherscan \
		-vvv

# Deploy dry-run commands (simulate without broadcasting)
deploy-dry-run-local:
	forge clean
	@echo "Simulating deployment to local network..."
	WETH_ADDRESS=${WETH_ADDRESS_SEPOLIA} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_SEPOLIA} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${LOCAL_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-dry-run-sepolia:
	forge clean
	@echo "Simulating deployment to Sepolia test network..."
	WETH_ADDRESS=${WETH_ADDRESS_SEPOLIA} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_SEPOLIA} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${SEPOLIA_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-dry-run-mainnet:
	forge clean
	@echo "Simulating deployment to Mainnet..."
	WETH_ADDRESS=${WETH_ADDRESS_MAINNET} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_MAINNET} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${MAINNET_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-dry-run-polygon:
	forge clean
	@echo "Simulating deployment to Polygon network..."
	WETH_ADDRESS=${WETH_ADDRESS_POLYGON} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_POLYGON} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${POLYGON_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

deploy-dry-run-bsc:
	forge clean
	@echo "Simulating deployment to BSC network..."
	WETH_ADDRESS=${WETH_ADDRESS_BSC} TOKEN_SUPPORT_ADDRESS=${TOKEN_SUPPORT_ADDRESS_BSC} \
	forge script ${DEPLOY_SCRIPT} \
		--rpc-url ${BSC_RPC} \
		--private-key ${PRIVATE_KEY} \
		-vvv

# Verify commands
verify-sepolia:
	@echo "Verifying contract on Sepolia..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/ProofOfCapital.sol:ProofOfCapital \
		--chain-id $$(cast chain-id --rpc-url ${SEPOLIA_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-mainnet:
	@echo "Verifying contract on Mainnet..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/ProofOfCapital.sol:ProofOfCapital \
		--chain-id $$(cast chain-id --rpc-url ${MAINNET_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-polygon:
	@echo "Verifying contract on Polygon..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/ProofOfCapital.sol:ProofOfCapital \
		--chain-id $$(cast chain-id --rpc-url ${POLYGON_RPC}) \
		--etherscan-api-key ${ETHERSCAN_API_KEY}
	@echo "Verification completed!"

verify-bsc:
	@echo "Verifying contract on BSC..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "Error: CONTRACT_ADDRESS not set"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) src/ProofOfCapital.sol:ProofOfCapital \
		--chain-id $$(cast chain-id --rpc-url ${BSC_RPC}) \
		--etherscan-api-key ${BSCSCAN_API_KEY}
	@echo "Verification completed!"

# Development helpers
dev-setup: install setup-env build test
	@echo "Development environment setup completed!"

check: build test lint
	@echo "All checks passed!"

help:
	@echo "Available commands:"
	@echo "  make build                    - Build contracts"
	@echo "  make test                     - Run tests"
	@echo "  make test-coverage            - Run tests with coverage"
	@echo "  make clean                    - Clean build artifacts"
	@echo "  make format                   - Format code"
	@echo "  make lint                     - Run linter"
	@echo "  make gas-report               - Generate gas usage report"
	@echo "  make install                  - Install dependencies"
	@echo "  make setup-env                - Setup environment file from example"
	@echo "  make check                    - Run all checks (build, test, lint)"
	@echo "  make dev-setup                - Complete development setup"
	@echo ""
	@echo "Deploy commands:"
	@echo "  make deploy-local             - Deploy to local network"
	@echo "  make deploy-sepolia           - Deploy to Sepolia with verification"
	@echo "  make deploy-mainnet           - Deploy to Mainnet with verification (use with caution!)"
	@echo "  make deploy-polygon           - Deploy to Polygon with verification"
	@echo "  make deploy-bsc               - Deploy to BSC with verification"
	@echo ""
	@echo "Deploy dry-run commands (simulate without broadcasting):"
	@echo "  make deploy-dry-run-local     - Simulate deployment to local network"
	@echo "  make deploy-dry-run-sepolia   - Simulate deployment to Sepolia"
	@echo "  make deploy-dry-run-mainnet   - Simulate deployment to Mainnet"
	@echo "  make deploy-dry-run-polygon   - Simulate deployment to Polygon"
	@echo "  make deploy-dry-run-bsc       - Simulate deployment to BSC"
	@echo ""
	@echo "Verify commands:"
	@echo "  make verify-sepolia           - Verify contract on Sepolia (requires CONTRACT_ADDRESS)"
	@echo "  make verify-mainnet           - Verify contract on Mainnet (requires CONTRACT_ADDRESS)"
	@echo "  make verify-polygon           - Verify contract on Polygon (requires CONTRACT_ADDRESS)"
	@echo "  make verify-bsc               - Verify contract on BSC (requires CONTRACT_ADDRESS)"
	@echo ""
	@echo "Before deploying, make sure to set up the required environment variables in .env file:"
	@echo "  - PRIVATE_KEY: Your private key for deployment"
	@echo "  - RPC_URL_SEPOLIA, RPC_URL_MAINNET, RPC_URL_POLYGON, RPC_URL_BSC: RPC URLs for the networks"
	@echo "  - WETH_ADDRESS_SEPOLIA, WETH_ADDRESS_MAINNET, WETH_ADDRESS_POLYGON, WETH_ADDRESS_BSC: WETH token addresses"
	@echo "  - TOKEN_SUPPORT_ADDRESS_SEPOLIA, TOKEN_SUPPORT_ADDRESS_MAINNET, TOKEN_SUPPORT_ADDRESS_POLYGON, TOKEN_SUPPORT_ADDRESS_BSC: Token support addresses"
	@echo "  - ETHERSCAN_API_KEY: Etherscan API key (for Ethereum networks)"
	@echo "  - BSCSCAN_API_KEY: BscScan API key (for BSC network)"
	@echo "  - CONTRACT_ADDRESS: Contract address (for verification)"
