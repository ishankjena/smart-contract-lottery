// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";


contract RaffleTest is Test {
	Raffle private raffle;
	HelperConfig private helperConfig;

	address public PLAYER = makeAddr("player1");
	uint256 public constant PLAYER_BALANCE = 10 ether;

	uint256 entranceFee;
	uint256 interval;
	address vrfCoordinator;
	bytes32 gasLane;
	uint64 subscriptionId;
	uint32 callbackGasLimit;
	address linkToken;

	/** EVENTS **/
	event UserEnteredRaffle__Event(address indexed player);

	// @dev create a mock PLAYER and give it some money to play
	function setUp() external {
		DeployRaffle deployer = new DeployRaffle();
		(raffle, helperConfig) = deployer.run();
		(
			entranceFee,
			interval,
			vrfCoordinator,
			gasLane,
			subscriptionId,
			callbackGasLimit,
			linkToken,

		) = helperConfig.activeConfig();
		vm.deal(PLAYER, PLAYER_BALANCE);
	}

	function testLotteryInitializesInOpenState() external view {
		assert (raffle.getLotteryState()==Raffle.LotteryState.OPEN);		
	}


	/**Tests for enterRaffe()**/

	function testRevertsWhenNotPaidEnoughEth() public {
		vm.startPrank(PLAYER);
		// expect this error
		vm.expectRevert(Raffle.Raffle__NotSentEnoughEthToBuyTicket__Error.selector);
		raffle.enterRaffle();
		vm.stopPrank();
	}

	function testRaffleRecordsPlayerOnEntering() public {
		vm.startPrank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		address playerRecorder = raffle.getPlayer(0);
		assert(playerRecorder==PLAYER);
		vm.stopPrank();
	}

	function testEmitsEventOnEntrance() public {
		vm.startPrank(PLAYER);

		// testing events
		// @dev EVENTS are not types, they cannot be imported. They have to be redefined.
		vm.expectEmit(true, false, false, false, address(raffle));
		emit UserEnteredRaffle__Event(PLAYER);		// expect this emit
		raffle.enterRaffle{value: entranceFee}();	// when this function is called

		vm.stopPrank();
	}

	// a subscription ID is required
	// On Sepolia: get from Chainlink VRF
	// On Local Anvil: create mock subscription, linkToken
	function testCannotEnterWhenLotteryPickingWinner() public {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		
		// pass time so that lottery ends (start picking winner)
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);
		raffle.performUpkeep("");

		vm.expectRevert(Raffle.Raffle__PickingLotteryWinner__Error.selector);
		
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
	}

	/** MODIFIERS **/
	modifier raffleEnteredAndTimePassed() { 
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);
		_;
	}

	modifier skipFork() {
		if(block.chainid!=31337){
			return;
		}
		_;
	}
	

	/** tests for checkUpkeep() **/

	// check if upkeep returns false due to no prize money (contract balance)
	function testCheckUpkeepReturnsFalseOnNoBalance() public {
		vm.warp(block.timestamp + interval + 1);
		vm.roll(block.number + 1);

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");

		assert(!upkeepNeeded);
	}

	function testCheckUpkeepReturnsFalseWhenPickingWinner()
		public raffleEnteredAndTimePassed {
		raffle.performUpkeep("");

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");
		assert(!upkeepNeeded);
	}

	function testCheckUpkeepReturnsFalseWhenNotEnoughTimeHasPassed() public {
		vm.prank(PLAYER);
		raffle.enterRaffle{value: entranceFee}();

		(bool upkeepNeeded, ) = raffle.checkUpkeep("");
		assert(!upkeepNeeded);
	}

	function testCheckUpkeepReturnsTrueForGoodParams()
		public raffleEnteredAndTimePassed {
		(bool upkeepNeeded, ) = raffle.checkUpkeep("");
		assert(upkeepNeeded);
	}


	/** tests for performUpkeep() **/
	function testPerformUpkeepCanOnlyRunWhenCheckUpkeepIsTrue()
		public raffleEnteredAndTimePassed {
		raffle.performUpkeep("");		
	}

	function testPerformUpkeepRevertsIfCheckUpkeepIsFalse()
		public skipFork {
		// expectRevert() with custom errors with parameters
		uint256 currentBalance = 0;
		uint256 numPlayers = 0;
		uint256 lotteryState = 0; // (OPEN)
		vm.expectRevert(
			abi.encodeWithSelector(
				Raffle.Raffle__UpkeepNotNeeded__Error.selector,
				lotteryState,
				currentBalance,
				numPlayers));
		raffle.performUpkeep("");
	}

	function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
		public raffleEnteredAndTimePassed {
		// access Logs and read all Emits
		vm.recordLogs();
		raffle.performUpkeep("");		// emits requestId
		Vm.Log[] memory entries = vm.getRecordedLogs();
		bytes32 requestId = entries[1].topics[1];

		Raffle.LotteryState lotteryState = raffle.getLotteryState();

		assert(uint256(requestId) > 0);
		assert(uint256(lotteryState)==1);	// PICKING WINNER (BUSY)
	}


	/** tests for fulfillRandomWOrds() **/

	// fuzz test
	function testFulfillRandomWordsIsCalledOnlyAfterPerformUpkeep(
		uint256 randomRequestId) public raffleEnteredAndTimePassed skipFork {
		vm.expectRevert("nonexistent request");
		VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
		// this simulation of vrfcoordinator only works on local testnet
		// On actual SEPOLIA TESTNET, the only the chainlink Coordinator is vrfCoordinator
	}

	function testFulfillRandomWordsPicksWinnerUpdatesVarsAndSendsPrize()
		public raffleEnteredAndTimePassed skipFork {
			// add "morePlayers" into lottery
			// total: (morePlayers+1) players
			uint256 morePlayers = 5;
			uint256 startIndex = 1;
			for(uint256 i=startIndex; i<startIndex+morePlayers; i++) {
				address player = address(uint160(i));
				hoax(player, PLAYER_BALANCE);
				raffle.enterRaffle{value: entranceFee}();
			}

			// get winning prize (to check later if winner gets the prize)
			uint256 prize = entranceFee * (morePlayers + 1);

			// get requestId
			vm.recordLogs();
			raffle.performUpkeep("");		// emits requestId
			Vm.Log[] memory entries = vm.getRecordedLogs();
			bytes32 requestId = entries[1].topics[1];

			uint256 prevTimeStamp = raffle.getLastTimeStamp();

			// pretend to be a vrfCoordinator and get random number
			VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
				uint256(requestId), address(raffle));

			// lottery simulation ends and new lottery opens
			assert(uint256(raffle.getLotteryState()) == 0);
			assert(raffle.getMostRecentWinner() != address(0));
			assert(raffle.getNumberOfPlayers() == 0);
			assert(prevTimeStamp < raffle.getLastTimeStamp());
			assert(raffle.getMostRecentWinner().balance == PLAYER_BALANCE + prize - entranceFee);
	}
}
