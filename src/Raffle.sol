// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author jenzen
 * @notice Create a simple raffle
 * @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {

	/** ERRORS **/
	error Raffle__NotSentEnoughEthToBuyTicket__Error();
	error Raffle__PrizeTransferFailed__Error();
	error Raffle__PickingLotteryWinner__Error();
	error Raffle__UpkeepNotNeeded__Error(LotteryState lotteryState, uint256 lotteryPrize, uint256 players);


	/** TYPE DECLARATIONS **/
	enum LotteryState { OPEN, PICKING_WINNER }
	// Here, OPEN:0, PICKING_WINNER:1


	/** STATE VARIABLES **/
	// @dev refer chainlink VRF subscription method docs
	uint16 private constant REQUEST_CONFIRMATIONS = 3;
	uint32 private constant NUM_WORDS = 1;
	// @dev ChainlinkVRF request coordinator, keyhash(gas lane),
	// callback function gas limit
	VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
	bytes32 private immutable i_gasLane;
	uint64 private immutable i_subscriptionId;
	uint32 private immutable i_callbackGasLimit;

	// @dev duration of the lottery (in seconds) 
	uint256 private immutable i_timeInterval;
	uint256 private immutable i_entranceFee;
	address payable[] private s_players;
	// @dev most recent timestamp of when a winner was picked
	// i.e. when the previous lottery ended
	uint256 private s_lastTimestamp;
	address payable private s_recentWinner;
	LotteryState private s_lotteryState;


	/** EVENTS **/
	event UserEnteredRaffle__Event(address indexed player);
	event PickedWinner__Event(address indexed winner);
	event RequestedRaffleWinner__Event(uint256 indexed requestId);

	/** CONSTRUCTOR **/
	constructor(
		uint256 _entranceFee,
		uint256 _interval,
		address _vrfCoordinator,
		bytes32 _gasLane,
		uint64 _subscriptionId,
		uint32 _callbackGasLimit
	) VRFConsumerBaseV2(_vrfCoordinator) {
		i_entranceFee = _entranceFee;
		i_timeInterval = _interval;
		// Lottery starts
		s_lotteryState = LotteryState.OPEN;
		s_lastTimestamp = block.timestamp;
		// @dev "i_vrfCoordinator" is the Chainlink VRF Coordinator Node to which we make requests for random number
		i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
		i_gasLane = _gasLane;
		i_subscriptionId = _subscriptionId;
		i_callbackGasLimit = _callbackGasLimit;
	} 

	/** FUNCTIONS **/
	function enterRaffle() external payable {
		if (msg.value < i_entranceFee){
			revert Raffle__NotSentEnoughEthToBuyTicket__Error();
		}
		if (s_lotteryState != LotteryState.OPEN) {
			revert Raffle__PickingLotteryWinner__Error();
		}
		s_players.push(payable(msg.sender));
		emit UserEnteredRaffle__Event(msg.sender);
	}


	// @dev The CHAINLINK Automation Nodes call this function "checkUpkeep()" to
	// decide when to "performUpkeep()"
	// checkUpkeep() returns true when:
	// 1. LotteryState is OPEN.
	// 2. i_timeInterval has passed between two lotteries.
	// 3. Subscription is funded with LINK.
	// 4. Contract has ETH.
	function checkUpkeep (bytes memory /*checkData*/) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
		bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_timeInterval;
		bool lotteryIsOpen = s_lotteryState==LotteryState.OPEN;
		bool contractHasBalance = address(this).balance > 0;
		bool hasPlayers = s_players.length > 0;
		upkeepNeeded = (timeHasPassed && lotteryIsOpen && contractHasBalance && hasPlayers);
	}

	// @dev pickWinner() [lottery logic] <=> performUpkeep() [chainlink automation]
	function performUpkeep(bytes calldata /*performData*/) external {
		(bool upkeepNeeded,) = checkUpkeep("");
		if (!upkeepNeeded) {
			revert Raffle__UpkeepNotNeeded__Error({
				lotteryState: s_lotteryState,
				lotteryPrize: address(this).balance,
				players: s_players.length
				});
		}

		s_lotteryState = LotteryState.PICKING_WINNER;

		// @dev get random number from <Chainlink VRF>
		// 1. make request to COORDINATOR
		uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedRaffleWinner__Event(requestId);
	}

	// @dev 2. USE the RANDOM NUMBER after getting it!
	// This is the callback Function that chainlinkVRF node call after getting
	// the random number(s)
	function fulfillRandomWords(
		uint256 /*_requestId*/,
		uint256[] memory _randomWords
		) internal override {
		// logic to PICK WINNER using the RANDOM NUMBER
		address payable winner = s_players[_randomWords[0] % s_players.length];
		
		// update variables
		s_recentWinner = winner;
		s_lotteryState = LotteryState.OPEN;
		s_players = new address payable[](0);
		s_lastTimestamp = block.timestamp;
		emit PickedWinner__Event(winner);
		// pay prize money to winner
		(bool success,) = winner.call{value: address(this).balance}("");
		if (!success) {
			revert Raffle__PrizeTransferFailed__Error();
		}
	}


	/** GETTER FUNCTIONS **/
	function getEntranceFee() external view returns (uint256) {
		return i_entranceFee;
	}

	function getLotteryState() external view returns (LotteryState) {
		return s_lotteryState;
	}

	function getLotteryDuration() external view returns (uint256) {
		return i_timeInterval;
	}

	function getMostRecentWinner() external view returns (address) {
		return s_recentWinner;
	}

	function getPlayer(uint256 playerIndex) external view returns (address) {
		return s_players[playerIndex];
	}

	function getNumberOfPlayers() external view returns(uint256) {
		return s_players.length;
	}

	function getLastTimeStamp() external view returns(uint256) {
		return s_lastTimestamp;
	}
}
