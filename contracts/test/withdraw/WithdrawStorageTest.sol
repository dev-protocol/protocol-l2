// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {WithdrawStorage} from "contracts/src/withdraw/WithdrawStorage.sol";

contract WithdrawStorageTest is WithdrawStorage {
	function setRewardsAmountTest(address _property, uint256 _value) external {
		setRewardsAmount(_property, _value);
	}

	function setCumulativePriceTest(address _property, uint256 _value)
		external
	{
		setCumulativePrice(_property, _value);
	}

	function setLastWithdrawalPriceTest(
		address _property,
		address _user,
		uint256 _value
	) external {
		setLastWithdrawalPrice(_property, _user, _value);
	}

	function setPendingWithdrawalTest(
		address _property,
		address _user,
		uint256 _value
	) external {
		setPendingWithdrawal(_property, _user, _value);
	}

	function setStorageLastWithdrawnRewardCapTest(
		address _property,
		address _user,
		uint256 _value
	) external {
		setStorageLastWithdrawnRewardCap(_property, _user, _value);
	}
}
