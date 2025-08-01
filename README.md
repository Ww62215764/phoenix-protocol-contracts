# Phoenix Protocol - Smart Contracts (Genesis Edition)

This repository contains the core smart contracts for the Phoenix Protocol, a next-generation, multi-chain DeFi liquidity engine.

## Overview

The system consists of four core, modular contracts:
*   **USDS.sol:** The protocol's native stablecoin, with minting/burning controlled by AccessControl.
*   **Vault.sol:** The central treasury, holding all user deposits and featuring a timelock and heartbeat mechanism for maximum security.
*   **Farm.sol:** The economic engine, handling all staking, yield, referral, and penalty logic.
*   **OracleManager.sol:** The risk management sentinel, monitoring for de-peg events.

## Prerequisites

*   Node.js (v18 or later)
*   NPM or Yarn

## Installation

1.  Clone the repository:
    ```bash
    git clone [your_repo_url]
    cd phoenix-protocol-contracts
    ```
2.  Install dependencies:
    ```bash
    npm install
    ```

## Configuration

1.  Create a `.env` file in the root of the project.
2.  Copy the contents of `.env.example` into `.env`.
3.  Fill in your own `ARBITRUM_RPC_URL` (from Alchemy/Infura) and your `PRIVATE_KEY` (from your deployer wallet).

```
# .env
ARBITRUM_RPC_URL="..."
PRIVATE_KEY="0x..."
```

## Core Commands

*   **Compile Contracts:**
    ```bash
    npx hardhat compile
    ```
*   **Run Tests:**
    ```bash
    npx hardhat test
    ```
*   **Deploy to Arbitrum Mainnet:**
    ```bash
    npx hardhat deploy --network arbitrum
    ```

## 🚨 CRITICAL: Post-Deployment Configuration

After running the deployment script, the contracts are **deployed but not yet fully operational**. You **MUST** execute a series of transactions via your **Safe Multi-sig Wallet** to finalize the setup and grant the necessary permissions.

The deployment script will output the exact function calls and parameters required. An example is provided below:

1.  **Set Farm Address in Vault:** `Vault.setFarmAddress(FARM_ADDRESS)`
2.  **Grant Minter Role to Farm:** `USDS.grantRole(MINTER_ROLE, FARM_ADDRESS)`
3.  **Grant Pauser Role to OracleManager:** `Vault.grantRole(PAUSER_ROLE, ORACLE_MANAGER_ADDRESS)`
4.  **Grant Keeper Role to Automation Bot:** `OracleManager.grantRole(KEEPER_ROLE, YOUR_BOT_ADDRESS)`

Only after these transactions are executed by the Admin Safe is the protocol considered fully armed and ready.
