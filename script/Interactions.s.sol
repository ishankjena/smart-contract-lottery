// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

// @dev
// Create a mock subcription id to connect the mock Chainlink VRF.

contract CreateSubscription is Script {

	function createSubscriptionUsingConfig() public returns (uint64) {
		HelperConfig helperConfig = new HelperConfig();
		(,,address vrfCoordinator,,,,,uint256 deployerKey) = helperConfig.activeConfig();
		return createSubscription(vrfCoordinator, deployerKey);
	}

	function createSubscription(address _vrfCoordinator, uint256 deployerKey) public returns (uint64) {
		console.log("Creating subscription on chainid: ", block.chainid);
		vm.startBroadcast(deployerKey);
		uint64 subId = VRFCoordinatorV2Mock(_vrfCoordinator).createSubscription();
		vm.stopBroadcast();
		console.log("Your subscription id is: ", subId);
		return subId;
	}

	function run() external returns (uint64) {
		return createSubscriptionUsingConfig();
	}
}


contract FundSubscription is Script {

	uint96 public constant FUND_AMOUNT = 3 ether;

	function fundSubscriptionUsingConfig() public {
		HelperConfig helperConfig = new HelperConfig();
		(,,address vrfCoordinator,,uint64 subcriptionID,,address link,uint256 deployerKey) = helperConfig.activeConfig();
		fundSubscription(vrfCoordinator, subcriptionID, link, deployerKey);
	}

	function fundSubscription(
		address _vrfCoordinator, uint64 _subscriptionId,
		address _link, uint256 deployerKey) public {
		console.log("Funding Subscription: ", _subscriptionId);
		console.log("Using vrfCoordinator: ", _vrfCoordinator);
		console.log("on chainid: ", block.chainid);

		if (block.chainid == 31337) {
			// fund (mock) subscription on LOCAL CHAIN
			vm.startBroadcast(deployerKey);
			VRFCoordinatorV2Mock(_vrfCoordinator).fundSubscription(
				_subscriptionId,
				FUND_AMOUNT
			);
			vm.stopBroadcast();
		}else{
			// Fund subscription on SEPOLIA CHAIN
			vm.startBroadcast(deployerKey);
			LinkToken(_link).transferAndCall(
				_vrfCoordinator,
				FUND_AMOUNT,
				abi.encode(_subscriptionId)
			);
			vm.stopBroadcast();
		}
	}

	function run() external {
		fundSubscriptionUsingConfig();
	}
}


contract AddConsumer is Script {

	function addConsumerUsingConfig(address _raffle) public {
		HelperConfig helperConfig = new HelperConfig();
		(,,address vrfCoordinator,,uint64 subcriptionID,,,uint256 deployerKey) = helperConfig.activeConfig();
		addConsumer(_raffle, vrfCoordinator, subcriptionID, deployerKey);
	}

	function addConsumer(address raffle, address vrfCoordinator, uint64 subcriptionID, uint256 deployerKey) public {
		console.log("Adding consumer contract: ", raffle);
		console.log("using vrfCoordinator: ", vrfCoordinator);
		console.log("on chainid", block.chainid);
		vm.startBroadcast(deployerKey);
		VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subcriptionID, raffle);
		vm.stopBroadcast();
	}

	// most recently deployed contract
	function run() external {
		address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
		addConsumerUsingConfig(raffle);
	}

}