// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Vault.sol";

contract OracleManager is AccessControl {
    AggregatorV3Interface public immutable priceFeed;
    Vault public immutable vault;
    uint256 public constant DEPEG_THRESHOLD = 5;
    uint256 public constant RECOVERY_THRESHOLD = 2;
    uint256 public depegCount;
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    event DepegPauseTriggered(uint256 percentDev);
    event DepegResumeTriggered();

    constructor(address _priceFeed, address _vault, address admin) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        vault = Vault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(KEEPER_ROLE, admin);
    }

    function checkDepeg() external onlyRole(KEEPER_ROLE) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Oracle: Invalid price");
        uint256 pegPrice = 10**priceFeed.decimals();
        uint256 deviation = uint256(price > int256(pegPrice) ? price - int256(pegPrice) : int256(pegPrice) - price);
        uint256 percentDev = deviation * 100 / pegPrice;

        if (percentDev > DEPEG_THRESHOLD) {
            depegCount++;
            if (depegCount >= 2 && !vault.paused()) {
                vault.pause();
                emit DepegPauseTriggered(percentDev);
            }
        } else if (percentDev < RECOVERY_THRESHOLD && vault.paused()) {
            depegCount = 0;
            vault.unpause();
            emit DepegResumeTriggered();
        } else {
            depegCount = 0;
        }

        vault.heartbeat();
    }
}
