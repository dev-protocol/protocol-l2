// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

// prettier-ignore
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Decimals} from "contracts/src/common/libs/Decimals.sol";
import {InitializableUsingRegistry} from "contracts/src/common/registry/InitializableUsingRegistry.sol";
import {IDevMinter} from "contracts/interface/IDevMinter.sol";
import {IProperty} from "contracts/interface/IProperty.sol";
import {IPolicy} from "contracts/interface/IPolicy.sol";
import {ILockup} from "contracts/interface/ILockup.sol";
import {IMetricsFactory} from "contracts/interface/IMetricsFactory.sol";

/**
 * A contract that manages the staking of DEV tokens and calculates rewards.
 * Staking and the following mechanism determines that reward calculation.
 *
 * Variables:
 * -`M`: Maximum mint amount per block determined by Allocator contract
 * -`B`: Number of blocks during staking
 * -`P`: Total number of staking locked up in a Property contract
 * -`S`: Total number of staking locked up in all Property contracts
 * -`U`: Number of staking per account locked up in a Property contract
 *
 * Formula:
 * Staking Rewards = M * B * (P / S) * (U / P)
 *
 * Note:
 * -`M`, `P` and `S` vary from block to block, and the variation cannot be predicted.
 * -`B` is added every time the Ethereum block is created.
 * - Only `U` and `B` are predictable variables.
 * - As `M`, `P` and `S` cannot be observed from a staker, the "cumulative sum" is often used to calculate ratio variation with history.
 * - Reward withdrawal always withdraws the total withdrawable amount.
 *
 * Scenario:
 * - Assume `M` is fixed at 500
 * - Alice stakes 100 DEV on Property-A (Alice's staking state on Property-A: `M`=500, `B`=0, `P`=100, `S`=100, `U`=100)
 * - After 10 blocks, Bob stakes 60 DEV on Property-B (Alice's staking state on Property-A: `M`=500, `B`=10, `P`=100, `S`=160, `U`=100)
 * - After 10 blocks, Carol stakes 40 DEV on Property-A (Alice's staking state on Property-A: `M`=500, `B`=20, `P`=140, `S`=200, `U`=100)
 * - After 10 blocks, Alice withdraws Property-A staking reward. The reward at this time is 5000 DEV (10 blocks * 500 DEV) + 3125 DEV (10 blocks * 62.5% * 500 DEV) + 2500 DEV (10 blocks * 50% * 500 DEV).
 */
contract Lockup is ILockup, InitializableUsingRegistry {
	using SafeMath for uint256;
	using Decimals for uint256;
	struct RewardPrices {
		uint256 reward;
		uint256 holders;
		uint256 interest;
		uint256 holdersCap;
	}
	event Lockedup(address _from, address _property, uint256 _value);
	event UpdateCap(uint256 _cap);

	uint256 public override cap; // From [get/set]StorageCap
	uint256 public override totalLocked; // From [get/set]StorageAllValue
	uint256 public cumulativeHoldersRewardCap; // From [get/set]StorageCumulativeHoldersRewardCap
	uint256 public lastCumulativeHoldersPriceCap; // From [get/set]StorageLastCumulativeHoldersPriceCap
	uint256 public lastLockedChangedCumulativeReward; // From [get/set]StorageLastStakesChangedCumulativeReward
	uint256 public lastCumulativeHoldersRewardPrice; // From [get/set]StorageLastCumulativeHoldersRewardPrice
	uint256 public lastCumulativeRewardPrice; // From [get/set]StorageLastCumulativeInterestPrice
	uint256 public cumulativeGlobalReward; // From [get/set]StorageCumulativeGlobalRewards
	uint256 public lastSameGlobalRewardAmount; // From [get/set]StorageLastSameRewardsAmountAndBlock
	uint256 public lastSameGlobalRewardBlock; // From [get/set]StorageLastSameRewardsAmountAndBlock
	mapping(address => uint256)
		public lastCumulativeHoldersRewardPricePerProperty; // {Property: Value} // [get/set]StorageLastCumulativeHoldersRewardPricePerProperty
	mapping(address => uint256) public initialCumulativeHoldersRewardCap; // {Property: Value} // From [get/set]StorageInitialCumulativeHoldersRewardCap
	mapping(address => uint256) public override totalLockedForProperty; // {Property: Value} // From [get/set]StoragePropertyValue
	mapping(address => uint256)
		public lastCumulativeHoldersRewardAmountPerProperty; // {Property: Value} // From [get/set]StorageLastCumulativeHoldersRewardAmountPerProperty
	mapping(address => mapping(address => uint256)) public override getValue; // {Property: {User: Value}} // From [get/set]StorageValue
	mapping(address => mapping(address => uint256)) public pendingReward; // {Property: {User: Value}} // From [get/set]StoragePendingInterestWithdrawal
	mapping(address => mapping(address => uint256)) public lastLockedPrice; // {Property: {User: Value}} // From [get/set]StorageLastStakedInterestPrice

	/**
	 * Initialize the passed address as AddressRegistry address.
	 */
	function initialize(address _registry) external initializer {
		__UsingRegistry_init(_registry);
	}

	/**
	 * Adds staking.
	 * Only the Dev contract can execute this function.
	 */
	function lockup(
		address _from,
		address _property,
		uint256 _value
	) external override {
		/**
		 * Validates the sender is Dev contract.
		 */
		require(
			msg.sender == registry().registries("Dev"),
			"this is illegal address"
		);

		/**
		 * Validates _value is not 0.
		 */
		require(_value != 0, "illegal lockup value");

		/**
		 * Validates the passed Property has greater than 1 asset.
		 */
		require(
			IMetricsFactory(registry().registries("MetricsFactory")).hasAssets(
				_property
			),
			"unable to stake to unauthenticated property"
		);

		/**
		 * Since the reward per block that can be withdrawn will change with the addition of staking,
		 * saves the undrawn withdrawable reward before addition it.
		 */
		RewardPrices memory prices = updatePendingInterestWithdrawal(
			_property,
			_from
		);

		/**
		 * Saves variables that should change due to the addition of staking.
		 */
		updateValues(true, _from, _property, _value, prices);

		emit Lockedup(_from, _property, _value);
	}

	/**
	 * Withdraw staking.
	 * Releases staking, withdraw rewards, and transfer the staked and withdraw rewards amount to the sender.
	 */
	function withdraw(address _property, uint256 _amount) external override {
		/**
		 * Validates the sender is staking to the target Property.
		 */
		require(
			hasValue(_property, msg.sender, _amount),
			"insufficient tokens staked"
		);

		/**
		 * Withdraws the staking reward
		 */
		RewardPrices memory prices = _withdrawInterest(_property);

		/**
		 * Transfer the staked amount to the sender.
		 */
		if (_amount != 0) {
			IProperty(_property).withdraw(msg.sender, _amount);
		}

		/**
		 * Saves variables that should change due to the canceling staking..
		 */
		updateValues(false, msg.sender, _property, _amount, prices);
	}

	/**
	 * set cap
	 */
	function updateCap(uint256 _cap) external override {
		address setter = IPolicy(registry().registries("Policy")).capSetter();
		require(setter == msg.sender, "illegal access");

		/**
		 * Updates cumulative amount of the holders reward cap
		 */
		(
			,
			uint256 holdersPrice,
			,
			uint256 cCap
		) = calculateCumulativeRewardPrices();

		// TODO: When this function is improved to be called on-chain, the source of `lastCumulativeHoldersPriceCap` can be rewritten to `lastCumulativeHoldersRewardPrice`.
		cumulativeHoldersRewardCap = cCap;
		lastCumulativeHoldersPriceCap = holdersPrice;
		cap = _cap;
		emit UpdateCap(_cap);
	}

	/**
	 * Returns the latest cap
	 */
	function _calculateLatestCap(uint256 _holdersPrice)
		private
		view
		returns (uint256)
	{
		uint256 cCap = cumulativeHoldersRewardCap;
		uint256 lastHoldersPrice = lastCumulativeHoldersPriceCap;
		uint256 additionalCap = _holdersPrice.sub(lastHoldersPrice).mul(cap);
		return cCap.add(additionalCap);
	}

	/**
	 * Store staking states as a snapshot.
	 */
	function beforeStakesChanged(
		address _property,
		address _user,
		RewardPrices memory _prices
	) private {
		/**
		 * Gets latest cumulative holders reward for the passed Property.
		 */
		uint256 cHoldersReward = _calculateCumulativeHoldersRewardAmount(
			_prices.holders,
			_property
		);

		/**
		 * Sets `InitialCumulativeHoldersRewardCap`.
		 * Records this value only when the "first staking to the passed Property" is transacted.
		 */
		if (
			lastCumulativeHoldersRewardPricePerProperty[_property] == 0 &&
			initialCumulativeHoldersRewardCap[_property] == 0 &&
			totalLockedForProperty[_property] == 0
		) {
			initialCumulativeHoldersRewardCap[_property] = _prices.holdersCap;
		}

		/**
		 * Store each value.
		 */
		lastLockedPrice[_property][_user] = _prices.interest;
		lastLockedChangedCumulativeReward = _prices.reward;
		lastCumulativeHoldersRewardPrice = _prices.holders;
		lastCumulativeRewardPrice = _prices.interest;
		lastCumulativeHoldersRewardAmountPerProperty[
			_property
		] = cHoldersReward;
		lastCumulativeHoldersRewardPricePerProperty[_property] = _prices
			.holders;
		cumulativeHoldersRewardCap = _prices.holdersCap;
		lastCumulativeHoldersPriceCap = _prices.holders;
	}

	/**
	 * Gets latest value of cumulative sum of the reward amount, cumulative sum of the holders reward per stake, and cumulative sum of the stakers reward per stake.
	 */
	function calculateCumulativeRewardPrices()
		public
		view
		override
		returns (
			uint256 _reward,
			uint256 _holders,
			uint256 _interest,
			uint256 _holdersCap
		)
	{
		uint256 lastReward = lastLockedChangedCumulativeReward;
		uint256 lastHoldersPrice = lastCumulativeHoldersRewardPrice;
		uint256 lastInterestPrice = lastCumulativeRewardPrice;
		uint256 allStakes = totalLocked;

		/**
		 * Gets latest cumulative sum of the reward amount.
		 */
		(uint256 reward, ) = dry();
		uint256 mReward = reward.mulBasis();

		/**
		 * Calculates reward unit price per staking.
		 * Later, the last cumulative sum of the reward amount is subtracted because to add the last recorded holder/staking reward.
		 */
		uint256 price = allStakes > 0
			? mReward.sub(lastReward).div(allStakes)
			: 0;

		/**
		 * Calculates the holders reward out of the total reward amount.
		 */
		uint256 holdersShare = IPolicy(registry().registries("Policy"))
			.holdersShare(price, allStakes);

		/**
		 * Calculates and returns each reward.
		 */
		uint256 holdersPrice = holdersShare.add(lastHoldersPrice);
		uint256 interestPrice = price.sub(holdersShare).add(lastInterestPrice);
		uint256 cCap = _calculateLatestCap(holdersPrice);
		return (mReward, holdersPrice, interestPrice, cCap);
	}

	/**
	 * Calculates cumulative sum of the holders reward per Property.
	 * To save computing resources, it receives the latest holder rewards from a caller.
	 */
	function _calculateCumulativeHoldersRewardAmount(
		uint256 _holdersPrice,
		address _property
	) private view returns (uint256) {
		(uint256 cHoldersReward, uint256 lastReward) = (
			lastCumulativeHoldersRewardAmountPerProperty[_property],
			lastCumulativeHoldersRewardPricePerProperty[_property]
		);

		/**
		 * `cHoldersReward` contains the calculation of `lastReward`, so subtract it here.
		 */
		uint256 additionalHoldersReward = _holdersPrice.sub(lastReward).mul(
			totalLockedForProperty[_property]
		);

		/**
		 * Calculates and returns the cumulative sum of the holder reward by adds the last recorded holder reward and the latest holder reward.
		 */
		return cHoldersReward.add(additionalHoldersReward);
	}

	/**
	 * Calculates cumulative sum of the holders reward per Property.
	 * caution!!!this function is deprecated!!!
	 * use calculateRewardAmount
	 */
	function calculateCumulativeHoldersRewardAmount(address _property)
		external
		view
		override
		returns (uint256)
	{
		(, uint256 holders, , ) = calculateCumulativeRewardPrices();
		return _calculateCumulativeHoldersRewardAmount(holders, _property);
	}

	/**
	 * Calculates holders reward and cap per Property.
	 */
	function calculateRewardAmount(address _property)
		external
		view
		override
		returns (uint256, uint256)
	{
		(
			,
			uint256 holders,
			,
			uint256 holdersCap
		) = calculateCumulativeRewardPrices();
		uint256 initialCap = initialCumulativeHoldersRewardCap[_property];

		/**
		 * Calculates the cap
		 */
		uint256 capValue = holdersCap.sub(initialCap);
		return (
			_calculateCumulativeHoldersRewardAmount(holders, _property),
			capValue
		);
	}

	/**
	 * Updates cumulative sum of the maximum mint amount calculated by Allocator contract, the latest maximum mint amount per block,
	 * and the last recorded block number.
	 * The cumulative sum of the maximum mint amount is always added.
	 * By recording that value when the staker last stakes, the difference from the when the staker stakes can be calculated.
	 */
	function update() public override {
		/**
		 * Gets the cumulative sum of the maximum mint amount and the maximum mint number per block.
		 */
		(uint256 _nextRewards, uint256 _amount) = dry();

		/**
		 * Records each value and the latest block number.
		 */
		cumulativeGlobalReward = _nextRewards;
		lastSameGlobalRewardAmount = _amount;
		lastSameGlobalRewardBlock = block.number;
	}

	/**
	 * @dev Returns the maximum number of mints per block.
	 * @return Maximum number of mints per block.
	 */
	function calculateMaxRewardsPerBlock() private view returns (uint256) {
		uint256 totalAssets = IMetricsFactory(
			registry().registries("MetricsFactory")
		).metricsCount();
		uint256 totalLockedUps = totalLocked;
		return
			IPolicy(registry().registries("Policy")).rewards(
				totalLockedUps,
				totalAssets
			);
	}

	/**
	 * Referring to the values recorded in each storage to returns the latest cumulative sum of the maximum mint amount and the latest maximum mint amount per block.
	 */
	function dry()
		private
		view
		returns (uint256 _nextRewards, uint256 _amount)
	{
		/**
		 * Gets the latest mint amount per block from Allocator contract.
		 */
		uint256 rewardsAmount = calculateMaxRewardsPerBlock();

		/**
		 * Gets the maximum mint amount per block, and the last recorded block number from `LastSameRewardsAmountAndBlock` storage.
		 */
		(uint256 lastAmount, uint256 lastBlock) = (
			lastSameGlobalRewardAmount,
			lastSameGlobalRewardBlock
		);

		/**
		 * If the recorded maximum mint amount per block and the result of the Allocator contract are different,
		 * the result of the Allocator contract takes precedence as a maximum mint amount per block.
		 */
		uint256 lastMaxRewards = lastAmount == rewardsAmount
			? rewardsAmount
			: lastAmount;

		/**
		 * Calculates the difference between the latest block number and the last recorded block number.
		 */
		uint256 blocks = lastBlock > 0 ? block.number.sub(lastBlock) : 0;

		/**
		 * Adds the calculated new cumulative maximum mint amount to the recorded cumulative maximum mint amount.
		 */
		uint256 additionalRewards = lastMaxRewards.mul(blocks);
		uint256 nextRewards = cumulativeGlobalReward.add(additionalRewards);

		/**
		 * Returns the latest theoretical cumulative sum of maximum mint amount and maximum mint amount per block.
		 */
		return (nextRewards, rewardsAmount);
	}

	/**
	 * Returns the staker reward as interest.
	 */
	function _calculateInterestAmount(address _property, address _user)
		private
		view
		returns (
			uint256 _amount,
			uint256 _interestPrice,
			RewardPrices memory _prices
		)
	{
		/**
		 * Get the amount the user is staking for the Property.
		 */
		uint256 lockedUpPerAccount = getValue[_property][_user];

		/**
		 * Gets the cumulative sum of the interest price recorded the last time you withdrew.
		 */
		uint256 lastInterest = lastLockedPrice[_property][_user];

		/**
		 * Gets the latest cumulative sum of the interest price.
		 */
		(
			uint256 reward,
			uint256 holders,
			uint256 interest,
			uint256 holdersCap
		) = calculateCumulativeRewardPrices();

		/**
		 * Calculates and returns the latest withdrawable reward amount from the difference.
		 */
		uint256 result = interest >= lastInterest
			? interest.sub(lastInterest).mul(lockedUpPerAccount).divBasis()
			: 0;
		return (
			result,
			interest,
			RewardPrices(reward, holders, interest, holdersCap)
		);
	}

	/**
	 * Returns the total rewards currently available for withdrawal. (For calling from inside the contract)
	 */
	function _calculateWithdrawableInterestAmount(
		address _property,
		address _user
	) private view returns (uint256 _amount, RewardPrices memory _prices) {
		/**
		 * If the passed Property has not authenticated, returns always 0.
		 */
		if (
			IMetricsFactory(registry().registries("MetricsFactory")).hasAssets(
				_property
			) == false
		) {
			return (0, RewardPrices(0, 0, 0, 0));
		}

		/**
		 * Gets the reward amount in saved without withdrawal.
		 */
		uint256 pending = pendingReward[_property][_user];

		/**
		 * Gets the latest withdrawal reward amount.
		 */
		(
			uint256 amount,
			,
			RewardPrices memory prices
		) = _calculateInterestAmount(_property, _user);

		/**
		 * Returns the sum of all values.
		 */
		uint256 withdrawableAmount = amount.add(pending);
		return (withdrawableAmount, prices);
	}

	/**
	 * Returns the total rewards currently available for withdrawal. (For calling from external of the contract)
	 */
	function calculateWithdrawableInterestAmount(
		address _property,
		address _user
	) public view override returns (uint256) {
		(uint256 amount, ) = _calculateWithdrawableInterestAmount(
			_property,
			_user
		);
		return amount;
	}

	/**
	 * Withdraws staking reward as an interest.
	 */
	function _withdrawInterest(address _property)
		private
		returns (RewardPrices memory _prices)
	{
		/**
		 * Gets the withdrawable amount.
		 */
		(
			uint256 value,
			RewardPrices memory prices
		) = _calculateWithdrawableInterestAmount(_property, msg.sender);

		/**
		 * Sets the unwithdrawn reward amount to 0.
		 */
		pendingReward[_property][msg.sender] = 0;

		/**
		 * Updates the staking status to avoid double rewards.
		 */
		lastLockedPrice[_property][msg.sender] = prices.interest;

		/**
		 * Mints the reward.
		 */
		require(
			IDevMinter(registry().registries("DevMinter")).mint(
				msg.sender,
				value
			),
			"dev mint failed"
		);

		/**
		 * Since the total supply of tokens has changed, updates the latest maximum mint amount.
		 */
		update();

		return prices;
	}

	/**
	 * Status updates with the addition or release of staking.
	 */
	function updateValues(
		bool _addition,
		address _account,
		address _property,
		uint256 _value,
		RewardPrices memory _prices
	) private {
		beforeStakesChanged(_property, _account, _prices);
		/**
		 * If added staking:
		 */
		if (_addition) {
			/**
			 * Updates the current staking amount of the protocol total.
			 */
			addAllValue(_value);

			/**
			 * Updates the current staking amount of the Property.
			 */
			addPropertyValue(_property, _value);

			/**
			 * Updates the user's current staking amount in the Property.
			 */
			addValue(_property, _account, _value);

			/**
			 * If released staking:
			 */
		} else {
			/**
			 * Updates the current staking amount of the protocol total.
			 */
			subAllValue(_value);

			/**
			 * Updates the current staking amount of the Property.
			 */
			subPropertyValue(_property, _value);

			/**
			 * Updates the current staking amount of the Property.
			 */
			subValue(_property, _account, _value);
		}

		/**
		 * Since each staking amount has changed, updates the latest maximum mint amount.
		 */
		update();
	}

	/**
	 * Adds the staking amount of the protocol total.
	 */
	function addAllValue(uint256 _value) private {
		uint256 value = totalLocked;
		value = value.add(_value);
		totalLocked = value;
	}

	/**
	 * Subtracts the staking amount of the protocol total.
	 */
	function subAllValue(uint256 _value) private {
		uint256 value = totalLocked;
		value = value.sub(_value);
		totalLocked = value;
	}

	/**
	 * Adds the user's staking amount in the Property.
	 */
	function addValue(
		address _property,
		address _sender,
		uint256 _value
	) private {
		uint256 value = getValue[_property][_sender];
		value = value.add(_value);
		getValue[_property][_sender] = value;
	}

	/**
	 * Subtracts the user's staking amount in the Property.
	 */
	function subValue(
		address _property,
		address _sender,
		uint256 _value
	) private {
		uint256 value = getValue[_property][_sender];
		value = value.sub(_value);
		getValue[_property][_sender] = value;
	}

	/**
	 * Returns whether the user is staking in the Property.
	 */
	function hasValue(
		address _property,
		address _sender,
		uint256 _amount
	) private view returns (bool) {
		uint256 value = getValue[_property][_sender];
		return value >= _amount;
	}

	/**
	 * Adds the staking amount of the Property.
	 */
	function addPropertyValue(address _property, uint256 _value) private {
		uint256 value = totalLockedForProperty[_property];
		value = value.add(_value);
		totalLockedForProperty[_property] = value;
	}

	/**
	 * Subtracts the staking amount of the Property.
	 */
	function subPropertyValue(address _property, uint256 _value) private {
		uint256 value = totalLockedForProperty[_property];
		uint256 nextValue = value.sub(_value);
		totalLockedForProperty[_property] = nextValue;
	}

	/**
	 * Saves the latest reward amount as an undrawn amount.
	 */
	function updatePendingInterestWithdrawal(address _property, address _user)
		private
		returns (RewardPrices memory _prices)
	{
		/**
		 * Gets the latest reward amount.
		 */
		(
			uint256 withdrawableAmount,
			RewardPrices memory prices
		) = _calculateWithdrawableInterestAmount(_property, _user);

		/**
		 * Saves the amount to `PendingInterestWithdrawal` storage.
		 */
		pendingReward[_property][_user] = withdrawableAmount;

		return prices;
	}
}
