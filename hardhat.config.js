// hardhat.config.js
require("@nomicfoundation/hardhat-ethers");
require("hardhat-deploy");
require("dotenv").config();

// --- 从.env文件中安全地读取机密信息 ---
const ARBITRUM_RPC_URL = process.env.ARBITRUM_RPC_URL || "https://arbitrum.llamarpc.com";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000000"; // 默认的空私钥

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337,
    },
    arbitrum: {
      url: ARBITRUM_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 42161,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0, // 使用 'accounts' 数组中的第一个私钥作为部署者
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
