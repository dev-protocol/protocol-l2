// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// prettier-ignore
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Decimals} from "contracts/src/common/libs/Decimals.sol";
import {UsingRegistry} from "contracts/src/common/registry/UsingRegistry.sol";
import {WithdrawStorage} from "contracts/src/withdraw/WithdrawStorage.sol";
import {IDevMinter} from "contracts/interface/IDevMinter.sol";
import {IWithdraw} from "contracts/interface/IWithdraw.sol";
import {ILockup} from "contracts/interface/ILockup.sol";
import {IMetricsGroup} from "contracts/interface/IMetricsGroup.sol";
import {IPropertyGroup} from "contracts/interface/IPropertyGroup.sol";

/**
 * A contract that manages the withdrawal of holder rewards for Property holders.
 */
contract Withdraw is IWithdraw, UsingRegistry, WithdrawStorage {
	using SafeMath for uint256;
	using Decimals for uint256;

	/**
	 * Initialize the passed address as AddressRegistry address.
	 */
	constructor(address _registry) UsingRegistry(_registry) {}

	/**
	 * Withdraws rewards.
	 */
	function withdraw(address _property) external override {
		/**
		 * Validate
		 * the passed Property address is included the Property address set.
		 */
		require(
			IPropertyGroup(registry().registries("PropertyGroup")).isGroup(
				_property
			),
			"this is illegal address"
		);

		/**
		 * Gets the withdrawable rewards amount and the latest cumulative sum of the maximum mint amount.
		 */
		(
			uint256 value,
			uint256 lastPrice,
			uint256 lastPriceCap,

		) = _calculateWithdrawableAmount(_property, msg.sender);

		/**
		 * Validates the result is not 0.
		 */
		require(value != 0, "withdraw value is 0");

		/**
		 * Saves the latest cumulative sum of the holder reward price.
		 * By subtracting this value when calculating the next rewards, always withdrawal the difference from the previous time.
		 */
		setStorageLastWithdrawnReward(_property, msg.sender, lastPrice);
		setStorageLastWithdrawnRewardCap(_property, msg.sender, lastPriceCap);

		/**
		 * Sets the number of unwithdrawn rewards to 0.
		 */
		setPendingWithdrawal(_property, msg.sender, 0);

		/**
		 * Updates the withdrawal status to avoid double withdrawal for before DIP4.
		 */
		__updateLegacyWithdrawableAmount(_property, msg.sender);

		/**
		 * Mints the holder reward.
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
		ILockup lockup = ILockup(registry().registries("Lockup"));
		lockup.update();

		/**
		 * Adds the reward amount already withdrawn in the passed Property.
		 */
		setRewardsAmount(_property, getRewardsAmount(_property).add(value));
	}

	/**
	 * Updates the change in compensation amount due to the change in the ownership ratio of the passed Property.
	 * When the ownership ratio of Property changes, the reward that the Property holder can withdraw will change.
	 * It is necessary to update the status before and after the ownership ratio changes.
	 */
	function beforeBalanceChange(address _from, address _to) external override {
		/**
		 * Validates the sender is Allocator contract.
		 */
		require(
			IPropertyGroup(registry().registries("PropertyGroup")).isGroup(
				msg.sender
			),
			"this is illegal address"
		);

		/**
		 * Gets the cumulative sum of the transfer source's "before transfer" withdrawable reward amount and the cumulative sum of the maximum mint amount.
		 */
		(
			uint256 amountFrom,
			uint256 priceFrom,
			uint256 priceCapFrom,

		) = _calculateAmount(msg.sender, _from);

		/**
		 * Gets the cumulative sum of the transfer destination's "before receive" withdrawable reward amount and the cumulative sum of the maximum mint amount.
		 */
		(
			uint256 amountTo,
			uint256 priceTo,
			uint256 priceCapTo,

		) = _calculateAmount(msg.sender, _to);

		/**
		 * Updates the last cumulative sum of the maximum mint amount of the transfer source and destination.
		 */
		setStorageLastWithdrawnReward(msg.sender, _from, priceFrom);
		setStorageLastWithdrawnReward(msg.sender, _to, priceTo);
		setStorageLastWithdrawnRewardCap(msg.sender, _from, priceCapFrom);
		setStorageLastWithdrawnRewardCap(msg.sender, _to, priceCapTo);

		/**
		 * Gets the unwithdrawn reward amount of the transfer source and destination.
		 */
		uint256 pendFrom = getPendingWithdrawal(msg.sender, _from);
		uint256 pendTo = getPendingWithdrawal(msg.sender, _to);

		/**
		 * Adds the undrawn reward amount of the transfer source and destination.
		 */
		setPendingWithdrawal(msg.sender, _from, pendFrom.add(amountFrom));
		setPendingWithdrawal(msg.sender, _to, pendTo.add(amountTo));

		emit PropertyTransfer(msg.sender, _from, _to);
	}

	/**
	 * Returns the holder reward.
	 */
	function _calculateAmount(address _property, address _user)
		private
		view
		returns (
			uint256 _amount,
			uint256 _price,
			uint256 _cap,
			uint256 _allReward
		)
	{
		ILockup lockup = ILockup(registry().registries("Lockup"));
		/**
		 * Gets the latest reward.
		 */
		(uint256 reward, uint256 cap) = lockup.calculateRewardAmount(_property);

		/**
		 * Gets the cumulative sum of the holder reward price recorded the last time you withdrew.
		 */

		uint256 allReward = _calculateAllReward(_property, _user, reward);
		uint256 capped = _calculateCapped(_property, _user, cap);
		uint256 value = capped == 0 ? allReward : allReward <= capped
			? allReward
			: capped;

		/**
		 * Returns the result after adjusted decimals to 10^18, and the latest cumulative sum of the holder reward price.
		 */
		return (value, reward, cap, allReward);
	}

	/**
	 * Return the reward cap
	 */
	function _calculateCapped(
		address _property,
		address _user,
		uint256 _cap
	) private view returns (uint256) {
		/**
		 * Gets the cumulative sum of the holder reward price recorded the last time you withdrew.
		 */
		uint256 _lastRewardCap = getStorageLastWithdrawnRewardCap(
			_property,
			_user
		);
		IERC20 property = IERC20(_property);
		uint256 balance = property.balanceOf(_user);
		uint256 totalSupply = property.totalSupply();
		uint256 unitPriceCap = _cap.sub(_lastRewardCap).div(totalSupply);
		return unitPriceCap.mul(balance).divBasis();
	}

	/**
	 * Return the reward
	 */
	function _calculateAllReward(
		address _property,
		address _user,
		uint256 _reward
	) private view returns (uint256) {
		/**
		 * Gets the cumulative sum of the holder reward price recorded the last time you withdrew.
		 */
		uint256 _lastReward = getStorageLastWithdrawnReward(_property, _user);
		IERC20 property = IERC20(_property);
		uint256 balance = property.balanceOf(_user);
		uint256 totalSupply = property.totalSupply();
		uint256 unitPrice = _reward.sub(_lastReward).mulBasis().div(
			totalSupply
		);
		return unitPrice.mul(balance).divBasis().divBasis();
	}

	/**
	 * Returns the total rewards currently available for withdrawal. (For calling from inside the contract)
	 */
	function _calculateWithdrawableAmount(address _property, address _user)
		private
		view
		returns (
			uint256 _amount,
			uint256 _price,
			uint256 _cap,
			uint256 _allReward
		)
	{
		/**
		 * Gets the latest withdrawal reward amount.
		 */
		(
			uint256 _value,
			uint256 price,
			uint256 cap,
			uint256 allReward
		) = _calculateAmount(_property, _user);

		/**
		 * If the passed Property has not authenticated, returns always 0.
		 */
		if (
			IMetricsGroup(registry().registries("MetricsGroup")).hasAssets(
				_property
			) == false
		) {
			return (0, price, cap, 0);
		}

		/**
		 * Gets the reward amount of before DIP4.
		 */
		uint256 legacy = __legacyWithdrawableAmount(_property, _user);

		/**
		 * Gets the reward amount in saved without withdrawal and returns the sum of all values.
		 */
		uint256 value = _value.add(getPendingWithdrawal(_property, _user)).add(
			legacy
		);
		return (value, price, cap, allReward);
	}

	/**
	 * Returns the total rewards currently available for withdrawal. (For calling from external of the contract)
	 * caution!!!this function is deprecated!!!
	 * use calculateRewardAmount
	 */
	function calculateWithdrawableAmount(address _property, address _user)
		external
		view
		override
		returns (uint256)
	{
		(uint256 value, , , ) = _calculateWithdrawableAmount(_property, _user);
		return value;
	}

	/**
	 * Returns the rewards amount
	 */
	function calculateRewardAmount(address _property, address _user)
		external
		view
		override
		returns (
			uint256 _amount,
			uint256 _price,
			uint256 _cap,
			uint256 _allReward
		)
	{
		return _calculateWithdrawableAmount(_property, _user);
	}

	/**
	 * Returns the reward amount of the calculation model before DIP4.
	 * It can be calculated by subtracting "the last cumulative sum of reward unit price" from
	 * "the current cumulative sum of reward unit price," and multiplying by the balance of the user.
	 */
	function __legacyWithdrawableAmount(address _property, address _user)
		private
		view
		returns (uint256)
	{
		uint256 _last = getLastWithdrawalPrice(_property, _user);
		uint256 price = getCumulativePrice(_property);
		uint256 priceGap = price.sub(_last);
		uint256 balance = IERC20(_property).balanceOf(_user);
		uint256 value = priceGap.mul(balance);
		return value.divBasis();
	}

	/**
	 * Updates and treats the reward of before DIP4 as already received.
	 */
	function __updateLegacyWithdrawableAmount(address _property, address _user)
		private
	{
		uint256 price = getCumulativePrice(_property);
		setLastWithdrawalPrice(_property, _user, price);
	}
}
