pragma solidity ^0.4.18;

import "./SafeMath.sol";
import "./GilgameshToken.sol";

/*
	Copyright 2017, Skiral Inc
*/
contract GilgameshTokenSale is SafeMath{

	// creationBlock is the block number that the Token was created
	uint256 public creationBlock;

	// startBlock token sale starting block
	uint256 public startBlock;

	// endBlock token sale ending block
	// end block is not a valid block for crowdfunding. endBlock - 1 is the last valid block
	uint256 public endBlock;

	// total Wei rasised
	uint256 public totalRaised = 0;

	// Has Gilgamesh stopped the sale
	bool public saleStopped = false;

	// Has Gilgamesh finalized the sale
	bool public saleFinalized = false;

	// Minimum purchase - 0.1 Ether
	uint256 constant public minimumInvestment = 100 finney;

	// Maximum hard Cap
	uint256 public hardCap = 50000 ether;

	// number of wei GIL tokens for sale - 60 Million GIL Tokens
	uint256 public tokenCap = 60000000 * 10**18;

	// Minimum cap
	uint256 public minimumCap = 1250 ether;

	/* Contract Info */

	// the deposit address for the Eth that is raised.
	address public fundOwnerWallet;

	// the deposit address for the tokens that is minted for the dev team.
	address public tokenOwnerWallet;

	// owner the address of the contract depoloyer
	address public owner;

	// List of stage bonus percentages in every stage
	// this will get generated in the constructor
	uint[] public stageBonusPercentage;

	// number of participants
	uint256 public totalParticipants;

	// a map of userId to wei
	mapping(uint256 => uint256) public paymentsByUserId;

	// a map of user address to wei
	mapping(address => uint256) public paymentsByAddress;

	// total number of bonus stages.
	uint8 public totalStages;

	// max bonus percentage on first stage
	uint8 public stageMaxBonusPercentage;

	// number of wei-GIL tokens for 1 wei (18 decimals)
	uint256 public tokenPrice;

	// the team owns 25% of the tokens - 3 times more than token purchasers.
	uint8 public teamTokenRatio = 3;

	// GIL token address
	GilgameshToken public token;

	// if Ether or Token cap has been reached
	bool public isCapReached = false;

	// log when token sale has been initialized
	event LogTokenSaleInitialized(
		address indexed owner,
		address indexed fundOwnerWallet,
		uint256 startBlock,
		uint256 endBlock,
		uint256 creationBlock
	);

	// log each contribution
	event LogContribution(
		address indexed contributorAddress,
		address indexed invokerAddress,
		uint256 amount,
		uint256 totalRaised,
		uint256 userAssignedTokens,
		uint256 indexed userId
	);

	// log when crowd fund is finalized
	event LogFinalized(address owner, uint256 teamTokens);

	// Constructor
	function GilgameshTokenSale(
		uint256 _startBlock, // starting block number
		uint256 _endBlock, // ending block number
		address _fundOwnerWallet, // fund owner wallet address - transfer ether to this address during and after fund has been closed
		address _tokenOwnerWallet, // token fund owner wallet address - transfer GIL tokens to this address after fund is finalized
		uint8 _totalStages, // total number of bonus stages
		uint8 _stageMaxBonusPercentage, // maximum percentage for bonus in the first stage
		uint256 _tokenPrice, // price of each GIL token in wei
		address _gilgameshToken, // address of the gilgamesh ERC20 token contract
		uint256 _minimumCap, // minimum cap, minimum amount of wei to be raised
		uint256 _tokenCap // tokenCap
	)
	public
	validate_address(_fundOwnerWallet) {

		if (
			_gilgameshToken == 0x0 ||
			_tokenOwnerWallet == 0x0 ||
			// start block needs to be in the future
			_startBlock < getBlockNumber()  ||
			// start block should be less than ending block
			_startBlock >= _endBlock  ||
			// minimum number of stages is 2
			_totalStages < 2 ||
			// verify stage max bonus
			_stageMaxBonusPercentage < 0  ||
			_stageMaxBonusPercentage > 100 ||
			// stage bonus percentage needs to be devisible by number of stages
			_stageMaxBonusPercentage % (_totalStages - 1) != 0 ||
			// total number of blocks needs to be devisible by the total stages
			(_endBlock - _startBlock) % _totalStages != 0
		) revert();

		owner = msg.sender; // make the contract creator the `owner`
		token = GilgameshToken(_gilgameshToken);
		endBlock = _endBlock;
		startBlock = _startBlock;
		creationBlock = getBlockNumber();
		fundOwnerWallet = _fundOwnerWallet;
		tokenOwnerWallet = _tokenOwnerWallet;
		tokenPrice = _tokenPrice;
		totalStages = _totalStages;
		minimumCap = _minimumCap;
		stageMaxBonusPercentage = _stageMaxBonusPercentage;
		totalRaised = 0; //	total number of wei raised
		tokenCap = _tokenCap;

		// spread bonuses evenly between stages - e.g 27 / 9 = 3%
		uint spread = stageMaxBonusPercentage / (totalStages - 1);

		// loop through [10 to 1] => ( 9 to 0) * 3% = [27%, 24%, 21%, 18%, 15%, 12%, 9%, 6%, 3%, 0%]
		for (uint stageNumber = totalStages; stageNumber > 0; stageNumber--) {
			stageBonusPercentage.push((stageNumber - 1) * spread);
		}

		LogTokenSaleInitialized(
			owner,
			fundOwnerWallet,
			startBlock,
			endBlock,
			creationBlock
		);
	}

	// --------------
	// Public Funtions
	// --------------

	/// @notice Function to stop sale for an emergency.
	/// @dev Only Gilgamesh Dev can do it after it has been activated.
	function emergencyStopSale()
	public
	only_sale_active
	onlyOwner {
		saleStopped = true;
	}

	/// @notice Function to restart stopped sale.
	/// @dev Only Gilgamesh Dev can do it after it has been disabled and sale has stopped.
	/// can it's in a valid time range for sale
	function restartSale()
	public
	only_during_sale_period
	only_sale_stopped
	onlyOwner {
		// if sale is finalized fail
		if (saleFinalized) revert();
		saleStopped = false;
	}

	/// @notice Function to change the fund owner wallet address
	/// @dev Only Gilgamesh Dev can trigger this function
	function changeFundOwnerWalletAddress(address _fundOwnerWallet)
	public
	validate_address(_fundOwnerWallet)
	onlyOwner {
		fundOwnerWallet = _fundOwnerWallet;
	}

	/// @notice Function to change the token fund owner wallet address
	/// @dev Only Gilgamesh Dev can trigger this function
	function changeTokenOwnerWalletAddress(address _tokenOwnerWallet)
	public
	validate_address(_tokenOwnerWallet)
	onlyOwner {
		tokenOwnerWallet = _tokenOwnerWallet;
	}

	/// @notice finalize the sale
	/// @dev Only Gilgamesh Dev can trigger this function
	function finalizeSale()
	public
	onlyOwner {
		doFinalizeSale();
	}

	/// @notice change hard cap and if it reaches hard cap finalize sale
	function changeCap(uint256 _cap)
	public
	onlyOwner {
		if (_cap < minimumCap) revert();
		if (_cap <= totalRaised) revert();

		hardCap = _cap;

		if (totalRaised + minimumInvestment >= hardCap) {
			isCapReached = true;
			doFinalizeSale();
		}
	}

	/// @notice change minimum cap, in case Ether price fluctuates.
	function changeMinimumCap(uint256 _cap)
	public
	onlyOwner {
		if (minimumCap < _cap) revert();
		minimumCap = _cap;
	}

	/// @notice remove conttact only when sale has been finalized
	/// transfer all the fund to the contract owner
	/// @dev only Gilgamesh Dev can trigger this function
	function removeContract()
	public
	onlyOwner {
		if (!saleFinalized) revert();
		selfdestruct(msg.sender);
	}

	/// @notice only the owner is allowed to change the owner.
	/// @param _newOwner the address of the new owner
	function changeOwner(address _newOwner)
	public
	validate_address(_newOwner)
	onlyOwner {
		require(_newOwner != owner);
		owner = _newOwner;
	}

	/// @dev The fallback function is called when ether is sent to the contract
	/// Payable is a required solidity modifier to receive ether
	/// every contract only has one unnamed function
	/// 2300 gas available for this function
	/*function () public payable {
		return deposit();
	}*/

	/**
	* Pay on a behalf of the sender.
	*
	* @param customerId Identifier in the central database, UUID v4
	*
	*/
	/// @dev allow purchasers to deposit ETH for GIL Tokens.
	function depositForMySelf(uint256 userId)
	public
	only_sale_active
	minimum_contribution()
	payable {
		deposit(userId, msg.sender);
	}

	///	@dev deposit() is an public function that accepts a userId and userAddress
	///	contract receives ETH in return of GIL tokens
	function deposit(uint256 userId, address userAddress)
	public
	payable
	only_sale_active
	minimum_contribution()
	validate_address(userAddress) {
		// if it passes hard cap throw
		if (totalRaised + msg.value > hardCap) revert();

		uint256 userAssignedTokens = calculateTokens(msg.value);

		// if user tokens are 0 throw
		if (userAssignedTokens <= 0) revert();

		// if number of tokens exceed the token cap stop execution
		if (token.totalSupply() + userAssignedTokens > tokenCap) revert();

		// send funds to fund owner wallet
		if (!fundOwnerWallet.send(msg.value)) revert();

		// mint tokens for the user
		if (!token.mint(userAddress, userAssignedTokens)) revert();

		// save total number wei raised
		totalRaised = safeAdd(totalRaised, msg.value);

		// if cap is reached mark it
		if (totalRaised >= hardCap) {
			isCapReached = true;
		}

		// if token supply has exceeded or reached the token cap stop
		if (token.totalSupply() >= tokenCap) {
			isCapReached = true;
		}

		// increase the number of participants for the first transaction
		if (paymentsByUserId[userId] == 0) {
			totalParticipants++;
		}

		// increase the amount that the user has payed
		paymentsByUserId[userId] += msg.value;

		// total wei based on address
		paymentsByAddress[userAddress] += msg.value;

		// log contribution event
		LogContribution(
			userAddress,
			msg.sender,
			msg.value,
			totalRaised,
			userAssignedTokens,
			userId
		);
	}

	/// @notice calculate number of tokens need to be issued based on the amount received
	/// @param amount number of wei received
	function calculateTokens(uint256 amount)
	public
	view
	returns (uint256) {
		// return 0 if the crowd fund has ended or it hasn't started
		if (!isDuringSalePeriod(getBlockNumber())) return 0;

		// get the current stage number by block number
		uint8 currentStage = getStageByBlockNumber(getBlockNumber());

		// if current stage is more than the total stage return 0 - something is wrong
		if (currentStage > totalStages) return 0;

		// calculate number of tokens that needs to be issued for the purchaser
		uint256 purchasedTokens = safeMul(amount, tokenPrice);
		// calculate number of tokens that needs to be rewraded to the purchaser
		uint256 rewardedTokens = calculateRewardTokens(purchasedTokens, currentStage);
		// add purchasedTokens and rewardedTokens
		return safeAdd(purchasedTokens, rewardedTokens);
	}

	/// @notice calculate reward based on amount of tokens that will be issued to the purchaser
	/// @param amount number tokens that will be minted for the purchaser
	/// @param stageNumber number of current stage in the crowd fund process
	function calculateRewardTokens(uint256 amount, uint8 stageNumber)
	public
	view
	returns (uint256 rewardAmount) {
		// throw if it's invalid stage number
		if (
			stageNumber < 1 ||
			stageNumber > totalStages
		) revert();

		// get stage index for the array
		uint8 stageIndex = stageNumber - 1;

		// calculate reward - e.q 100 token creates 100 * 20 /100 = 20 tokens for reward
		return safeDiv(safeMul(amount, stageBonusPercentage[stageIndex]), 100);
	}

	/// @notice get crowd fund stage by block number
	/// @param _blockNumber block number
	function getStageByBlockNumber(uint256 _blockNumber)
	public
	view
	returns (uint8) {
		// throw error, if block number is out of range
		if (!isDuringSalePeriod(_blockNumber)) revert();

		uint256 totalBlocks = safeSub(endBlock, startBlock);
		uint256 numOfBlockPassed = safeSub(_blockNumber, startBlock);

		// since numbers round down we need to add one to number of stage
		return uint8(safeDiv(safeMul(totalStages, numOfBlockPassed), totalBlocks) + 1);
	}

	// --------------
	// Internal Funtions
	// --------------

	/// @notice check if the block number is during the sale period
	/// @param _blockNumber block number
	function isDuringSalePeriod(uint256 _blockNumber)
	view
	internal
	returns (bool) {
		return (_blockNumber >= startBlock && _blockNumber < endBlock);
	}

	/// @notice finalize the crowdfun sale
	/// @dev Only Gilgamesh Dev can trigger this function
	function doFinalizeSale()
	internal
	onlyOwner {

		if (saleFinalized) revert();

		// calculate the number of tokens that needs to be assigned to Gilgamesh team
		uint256 teamTokens = safeMul(token.totalSupply(), teamTokenRatio);

		if (teamTokens > 0){
			// mint tokens for the team
			if (!token.mint(tokenOwnerWallet, teamTokens)) revert();
		}

		// if there is any fund drain it
		if(this.balance > 0) {
			// send ether funds to fund owner wallet
			if (!fundOwnerWallet.send(this.balance)) revert();
		}

		// finalize sale flag
		saleFinalized = true;

		// stop sale flag
		saleStopped = true;

		// log finalized
		LogFinalized(tokenOwnerWallet, teamTokens);
	}

	/// @notice returns block.number
	function getBlockNumber() constant internal returns (uint) {
		return block.number;
	}

	// --------------
	// Modifiers
	// --------------

	/// continue only when sale has stopped
	modifier only_sale_stopped {
		if (!saleStopped) revert();
		_;
	}


	/// validates an address - currently only checks that it isn't null
	modifier validate_address(address _address) {
		if (_address == 0x0) revert();
		_;
	}

	/// continue only during the sale period
	modifier only_during_sale_period {
		// if block number is less than starting block fail
		if (getBlockNumber() < startBlock) revert();
		// if block number has reach to the end block fail
		if (getBlockNumber() >= endBlock) revert();
		// otherwise safe to continue
		_;
	}

	/// continue when sale is active and valid
	modifier only_sale_active {
		// if sale is finalized fail
		if (saleFinalized) revert();
		// if sale is stopped fail
		if (saleStopped) revert();
		// if cap is reached
		if (isCapReached) revert();
		// if block number is less than starting block fail
		if (getBlockNumber() < startBlock) revert();
		// if block number has reach to the end block fail
		if (getBlockNumber() >= endBlock) revert();
		// otherwise safe to continue
		_;
	}

	/// continue if minimum contribution has reached
	modifier minimum_contribution() {
		if (msg.value < minimumInvestment) revert();
		_;
	}

	/// continue when the invoker is the owner
	modifier onlyOwner() {
		if (msg.sender != owner) revert();
		_;
	}
}
