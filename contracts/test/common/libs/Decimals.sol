// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.9;

import "../../../src/common/libs/Decimals.sol";

contract DecimalsTest {
	using Decimals for uint256;

	function outOf(
		uint256 _a,
		uint256 _b
	) external pure returns (uint256 result) {
		return _a.outOf(_b);
	}

	function mulBasis(uint256 _a) external pure returns (uint256 result) {
		return _a.mulBasis();
	}

	function divBasis(uint256 _a) external pure returns (uint256 result) {
		return _a.divBasis();
	}
}
