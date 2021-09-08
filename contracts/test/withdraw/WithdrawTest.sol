// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {Withdraw} from "contracts/src/withdraw/Withdraw.sol";

contract WithdrawTest is Withdraw {
	constructor() Withdraw() {}

	function __setLastWithdrawnRewardPrice(
		address _property,
		address _user,
		uint256 _value
	) external {
		lastWithdrawnRewardPrice[_property][_user] = _value;
	}
}
