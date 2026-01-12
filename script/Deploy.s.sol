// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {JuiceRoule} from "../src/JuiceRoule.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";

/// @title Deploy - JuiceRoule deployment script
/// @notice Deploys JuiceRoule and its LiquidityPool to the target network
contract Deploy is Script {
    function run() public returns (JuiceRoule roulette, LiquidityPool pool) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy JuiceRoule (which internally deploys LiquidityPool)
        roulette = new JuiceRoule();
        pool = roulette.pool();

        console.log("JuiceRoule deployed at:", address(roulette));
        console.log("LiquidityPool deployed at:", address(pool));

        vm.stopBroadcast();
    }
}

/// @title DeployWithLiquidity - Deploy and seed initial liquidity
/// @notice Deploys JuiceRoule and adds initial liquidity to the pool
contract DeployWithLiquidity is Script {
    function run() public returns (JuiceRoule roulette, LiquidityPool pool) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialLiquidity = vm.envOr("INITIAL_LIQUIDITY", uint256(1 ether));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy JuiceRoule
        roulette = new JuiceRoule();
        pool = roulette.pool();

        // Add initial liquidity
        pool.deposit{value: initialLiquidity}();

        console.log("JuiceRoule deployed at:", address(roulette));
        console.log("LiquidityPool deployed at:", address(pool));
        console.log("Initial liquidity:", initialLiquidity);

        vm.stopBroadcast();
    }
}
