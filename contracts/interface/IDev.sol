// SPDX-License-Identifier: MPL-2.0
// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

interface IDev {
	function mint(address _account, uint256 _amount) external;

	function burn(address _account, uint256 _amount) external;
}
