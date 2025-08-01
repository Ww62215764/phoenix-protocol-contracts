// deploy/01-deploy-phoenix.js
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();

    // --- 在此配置最终的、不可更改的创世参数 ---
    const SAFE_ADMIN_ADDRESS = "YOUR_SAFE_WALLET_ADDRESS"; // 【重要】你的Safe多签钱包地址
    const USDT_ADDRESS_ARBITRUM = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"; // Arbitrum USDT地址
    const PRICE_FEED_ADDRESS_ARBITRUM = "0x3f3f5dF88dC9F13eAC63DF89EC16ef6e7E25DdE7"; // Arbitrum Chainlink USDT/USD Feed
    const USDS_CAP = ethers.parseEther("1000000000"); // USDS最大供应量：10亿

    log("====================================================");
    log("🚀 Starting Deployment of Phoenix Protocol...");
    log("Deployer Account:", deployer);
    log("====================================================");

    // 1. 部署 USDS.sol
    const usds = await deploy("USDS", {
        from: deployer,
        args: [USDS_CAP, SAFE_ADMIN_ADDRESS],
        log: true,
        waitConfirmations: network.config.chainId === 42161 ? 3 : 1,
    });
    log(`✅ USDS deployed at: ${usds.address}`);

    // 2. 部署 Vault.sol
    const vault = await deploy("Vault", {
        from: deployer,
        args: [USDT_ADDRESS_ARBITRUM, SAFE_ADMIN_ADDRESS],
        log: true,
        waitConfirmations: network.config.chainId === 42161 ? 3 : 1,
    });
    log(`✅ Vault deployed at: ${vault.address}`);

    // 3. 部署 OracleManager.sol
    const oracleManager = await deploy("OracleManager", {
        from: deployer,
        args: [PRICE_FEED_ADDRESS_ARBITRUM, vault.address, SAFE_ADMIN_ADDRESS],
        log: true,
        waitConfirmations: network.config.chainId === 42161 ? 3 : 1,
    });
    log(`✅ OracleManager deployed at: ${oracleManager.address}`);

    // 4. 部署 Farm.sol
    const farm = await deploy("Farm", {
        from: deployer,
        args: [usds.address, vault.address, SAFE_ADMIN_ADDRESS],
        log: true,
        waitConfirmations: network.config.chainId === 42161 ? 3 : 1,
    });
    log(`✅ Farm deployed at: ${farm.address}`);

    log("\n====================================================");
    log("🔥 Phoenix Protocol Contracts Deployed Successfully!");
    log("====================================================");
    log("📋 CRITICAL NEXT STEP: Execute the following configuration");
    log("   transactions via your Safe Multi-sig Wallet (" + SAFE_ADMIN_ADDRESS + ")");
    log("----------------------------------------------------");
    log(`1. Target: Vault (${vault.address})`);
    log(`   Function: setFarmAddress(address _farm)`);
    log(`   Parameter _farm: ${farm.address}\n`);

    log(`2. Target: USDS (${usds.address})`);
    log(`   Function: grantRole(bytes32 role, address account)`);
    log(`   Parameter role (MINTER_ROLE): ${await usdsContract.MINTER_ROLE()}`); // 假设usdsContract已加载
    log(`   Parameter account: ${farm.address}\n`);
    
    log(`3. Target: Vault (${vault.address})`);
    log(`   Function: grantRole(bytes32 role, address account)`);
    log(`   Parameter role (PAUSER_ROLE): ${await vaultContract.PAUSER_ROLE()}`); // 假设vaultContract已加载
    log(`   Parameter account: ${oracleManager.address}\n`);

    log(`4. Target: OracleManager (${oracleManager.address})`);
    log(`   Function: grantRole(bytes32 role, address account)`);
    log(`   Parameter role (KEEPER_ROLE): ${await oracleManagerContract.KEEPER_ROLE()}`); // 假设oracleManagerContract已加载
    log(`   Parameter account: YOUR_AUTOMATION_BOT_ADDRESS\n`);
    log("====================================================");
};

module.exports.tags = ["all", "phoenix"];
