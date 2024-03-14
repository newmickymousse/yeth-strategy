-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

FORK_URL := ${ETH_RPC_URL} 
FORK_BLOCK_NUMBER := 19435506

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
trace  :; forge test -vvv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
gas  :; forge test --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --gas-report
test-contract  :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace-contract  :; forge test -vvv --match-contract $(contract) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
test-test  :; forge test -vv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
trace-test  :; forge test -vvv --match-test $(test) --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --fork-block-number ${FORK_BLOCK_NUMBER}
snapshot :; forge snapshot -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
snapshot-diff :; forge snapshot --diff -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}


clean  :; forge clean
