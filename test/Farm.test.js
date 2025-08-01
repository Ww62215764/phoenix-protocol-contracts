// test/Farm.test.js
const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("Phoenix Protocol: Core Logic", function () {
    let deployer, user1, user2, referrer;
    let usds, vault, farm, oracleManager;

    // 使用Fixture，一次性部署整个测试环境
    async function deployPhoenixFixture() {
        [deployer, user1, user2, referrer] = await ethers.getSigners();
        
        // 部署USDS
        const USDS = await ethers.getContractFactory("USDS");
        usds = await USDS.deploy(ethers.parseEther("1000000000"), deployer.address);
        
        // 部署Vault
        const MockUSDT = await ethers.getContractFactory("ERC20Mock"); // 使用一个模拟的USDT
        const usdt = await MockUSDT.deploy("Mock USDT", "mUSDT");
        const Vault = await ethers.getContractFactory("Vault");
        vault = await Vault.deploy(usdt.address, deployer.address);
        
        // 部署Farm
        const Farm = await ethers.getContractFactory("Farm");
        farm = await Farm.deploy(usds.address, vault.address, deployer.address);
        
        // 配置权限
        await vault.setFarmAddress(farm.address);
        await usds.grantRole(await usds.MINTER_ROLE(), farm.address);
        
        // 给用户分发初始资金
        await usdt.transfer(user1.address, ethers.parseEther("10000"));
        
        return { usds, vault, farm, usdt, deployer, user1, user2, referrer };
    }

    describe("Deployment & Core Functions", function () {
        beforeEach(async function () {
            await loadFixture(deployPhoenixFixture);
        });

        it("Should allow a user to mint and lock correctly", async function () {
            const lockAmount = ethers.parseEther("1000");
            
            // 用户 mint
            await usdt.connect(user1).approve(farm.address, lockAmount); // 授权Farm使用USDT
            await farm.connect(user1).mint(lockAmount, referrer.address);
            expect(await usds.balanceOf(user1.address)).to.equal(lockAmount);

            // 用户 lock
            await usds.connect(user1).approve(farm.address, lockAmount); // 授权Farm使用USDS
            await expect(farm.connect(user1).lock(lockAmount, 5 * 24 * 3600))
                .to.emit(farm, "Locked")
                .withArgs(user1.address, lockAmount, 5 * 24 * 3600);

            const userInfo = await farm.users(user1.address);
            expect(userInfo.amount).to.equal(lockAmount);
        });

        it("Should calculate withdrawal fee correctly based on time", async function () {
            // ... 测试罚金逻辑
            // 1. 锁仓
            // 2. 使用 network.provider.send("evm_increaseTime", [seconds]) 来快进时间
            // 3. 提款并验证罚金
        });
        
        it("Should prevent referral farming via 3-day validation", async function () {
            // ... 测试防刷返佣逻辑
            // 1. user1 锁仓，推荐人为 referrer
            // 2. 立即让 referrer 调用 processMyCommissions，应该失败或无效果
            // 3. 快进时间超过3天
            // 4. 再次让 referrer 调用，应该成功
        });
    });
});
