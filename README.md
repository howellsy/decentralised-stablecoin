# DSC 🪙 _the_ decentralised stablecoin

DSC is a decentralised stablecoin pegged to USD and **fully backed** by wETH and wBTC. It features:

➡️ Relative stability (anchored to $1 USD)

➡️ An algorithmic stability mechanism

➡️ Exogenous collateral: fully backed by wETH and wBTC

It leverages:

-   Chainlink's `AggregatorV3Interface` data feeds for retrieving token values in USD

## ⚒️ Built with Foundry

This project is built with [Foundry](https://github.com/foundry-rs/foundry) a portable and modular toolkit for Ethereum application development, which is required to build and deploy the project.

## 🏗️ Getting started

Create a `.env` file with the following entries:

```
SEPOLIA_RPC_URL=<sepolia_rpc_url>
PRIVATE_KEY=<private_key>
ETHERSCAN_API_KEY=<etherscan_api_key>
```

Install project dependencies

```
make install
```

Deploy the smart contract on Anvil

```
make anvil
make deploy
```

Deploy the smart contract on Sepolia

```
make deploy ARGS="--network sepolia"
```

## 🧪 Running tests

The project contains a suite of unit and invariant (fuzz) tests. To run against a local Anvil Ethereum node:

```
forge test
```

To run against a forked environment (e.g. a forked Sepolia testnet):

```
forge test --fork-url <sepolia_rpc_url>
```
