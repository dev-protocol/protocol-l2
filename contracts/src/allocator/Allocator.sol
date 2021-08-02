pragma solidity 0.5.17;

import {UsingRegistry} from "contracts/src/common/registry/UsingRegistry.sol";
import {IAllocator} from "contracts/interface/IAllocator.sol";
import {IWithdraw} from "contracts/interface/IWithdraw.sol";
import {IPolicy} from "contracts/interface/IPolicy.sol";
import {ILockup} from "contracts/interface/ILockup.sol";
import {IPropertyGroup} from "contracts/interface/IPropertyGroup.sol";
import {IMetricsGroup} from "contracts/interface/IMetricsGroup.sol";

/**
 * A contract that determines the total number of mint.
 * Lockup contract and Withdraw contract mint new DEV tokens based on the total number of new mint determined by this contract.
 */
contract Allocator is UsingRegistry, IAllocator {
	/**
	 * @dev Initialize the passed address as AddressConfig address.
	 * @param _config AddressConfig address.
	 */
	constructor(address _config) public UsingRegistry(_config) {}

	/**
	 * @dev Returns the maximum number of mints per block.
	 * @return Maximum number of mints per block.
	 */
	function calculateMaxRewardsPerBlock() external view returns (uint256) {
		uint256 totalAssets = IMetricsGroup(
			registry().registries("MetricsGroup")
		).totalIssuedMetrics();
		uint256 totalLockedUps = ILockup(registry().registries("Lockup"))
			.getAllValue();
		return
			IPolicy(registry().registries("Policy")).rewards(
				totalLockedUps,
				totalAssets
			);
	}

	/**
	 * @dev Passthrough to `Withdraw.beforeBalanceChange` funtion.
	 * @param _property Address of the Property address to transfer.
	 * @param _from Address of the sender.
	 * @param _to Address of the recipient.
	 */
	function beforeBalanceChange(
		address _property,
		address _from,
		address _to
	) external {
		require(
			IPropertyGroup(registry().registries("PropertyGroup")).isGroup(
				msg.sender
			),
			"this is illegal address"
		);

		IWithdraw(registry().registries("Withdraw")).beforeBalanceChange(
			_property,
			_from,
			_to
		);
	}
}
