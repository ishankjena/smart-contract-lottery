// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;


import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, AddConsumer, FundSubscription} from "./Interactions.s.sol";

contract DeployRaffle is Script {
	function run () external returns(Raffle, HelperConfig) {
		HelperConfig helperConfig = new HelperConfig();
		(
			uint256 entranceFee,
			uint256 interval,
			address vrfCoordinator,
			bytes32 gasLane,
			uint64 subscriptionId,
			uint32 callbackGasLimit,
			address linkToken,
			uint256 deployerKey
		) = helperConfig.activeConfig();

		if (subscriptionId==0) {
			CreateSubscription newSubscription = new CreateSubscription();
			subscriptionId = newSubscription.createSubscription(vrfCoordinator, deployerKey);

			// fund the subscription after creating it
			FundSubscription fundSubscription = new FundSubscription();
			fundSubscription.fundSubscription(vrfCoordinator, subscriptionId, linkToken, deployerKey);
		}

		vm.startBroadcast();
		Raffle raffle = new Raffle(
			entranceFee,
			interval,
			vrfCoordinator,
			gasLane,
			subscriptionId,
			callbackGasLimit);
		vm.stopBroadcast();

		// Add consumer after funding
		AddConsumer addConsumer = new AddConsumer();
		addConsumer.addConsumer(address(raffle), vrfCoordinator, subscriptionId, deployerKey);

		return (raffle, helperConfig);
	}
	
}

