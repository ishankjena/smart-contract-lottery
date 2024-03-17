// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

/**
 * @dev refer: https://docs.chain.link/vrf/v2/subscription/supported-networks
 * */

contract HelperConfig is Script {

	struct NetworkConfig {
		uint256 _entranceFee;
		uint256 _interval;
		address _vrfCoordinator;
		bytes32 _gasLane;
		uint64 _subscriptionId;
		uint32 _callbackGasLimit;
		address _linkToken;
		uint256 deployerKey;		
	}
	
	uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
	NetworkConfig public activeConfig;

	constructor() {
		if(block.chainid==11155111){
			activeConfig = getSepoliaEthConfig();
		}else{
			activeConfig = getOrCreateAnvilEthConfig();
		}

	}

	function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
		return NetworkConfig({
			_entranceFee: 0.01 ether,
			_interval: 30,
			_vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,	// from Chainlink docs
			_gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,	// from Chainlink docs
			_subscriptionId: 10126, // created by me on vrf.chain.link
			_callbackGasLimit: 500000,
			_linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // from Chainlink docs
			deployerKey: vm.envUint("VRF_ACCOUNT_PRIVATE_KEY")
			});
	}

	function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
		if(activeConfig._vrfCoordinator != address(0)){
			return activeConfig;
		}

		// @dev constructor params for VRFCoordinatorV2Mock objects:
		uint96 baseFee = 0.25 ether;
		uint96 gasPriceLink = 1e9;

		// @dev create MOCK vrfCoordinator and MOCK LINK
		vm.startBroadcast();
		VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
		LinkToken link = new LinkToken();
		vm.stopBroadcast();

		return NetworkConfig({
			_entranceFee: 0.01 ether,
			_interval: 30,
			_vrfCoordinator: address(vrfCoordinatorMock),
			_gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
			_subscriptionId: 0, // auto updates (mock)
			_callbackGasLimit: 500000,
			_linkToken: address(link),
			deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
			});
	}
}
