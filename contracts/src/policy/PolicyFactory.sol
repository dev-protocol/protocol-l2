// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {InitializableUsingRegistry} from "contracts/src/common/registry/InitializableUsingRegistry.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPolicy} from "contracts/interface/IPolicy.sol";
import {IPolicyFactory} from "contracts/interface/IPolicyFactory.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * A factory contract that creates a new Policy contract.
 */
contract PolicyFactory is
	InitializableUsingRegistry,
	OwnableUpgradeable,
	IPolicyFactory
{
	using SafeMath for uint256;

	mapping(address => bool) public override isPotentialPolicy;
	mapping(address => uint256) public override closeVoteAt;

	/**
	 * Initialize the passed address as AddressRegistry address.
	 */
	function initialize(address _registry) external initializer {
		__Ownable_init();
		__UsingRegistry_init(_registry);
	}

	/**
	 * Creates a new Policy contract.
	 */
	function create(address _newPolicyAddress) external override {
		/**
		 * Validates the passed address is not 0 address.
		 */
		require(_newPolicyAddress != address(0), "this is illegal address");

		emit Create(msg.sender, _newPolicyAddress);

		/**
		 * In the case of the first Policy, it will be activated immediately.
		 */
		if (registry().registries("Policy") == address(0)) {
			registry().setRegistry("Policy", _newPolicyAddress);
		}

		/**
		 * Adds the created Policy contract to the Policy address set.
		 */
		_addPolicy(_newPolicyAddress);
	}

	/**
	 * Set the policy to force a policy without a vote.
	 */
	function forceAttach(address _policy) external override onlyOwner {
		/**
		 * Validates the passed Policy address is included the Policy address set
		 */
		require(isPotentialPolicy[_policy], "this is illegal address");
		/**
		 * Validates the voting deadline has not passed.
		 */
		require(isDuringVotingPeriod(_policy), "deadline is over");

		/**
		 * Sets the passed Policy to current Policy.
		 */
		registry().setRegistry("Policy", _policy);
	}

	function _addPolicy(address _addr) internal {
		isPotentialPolicy[_addr] = true;

		uint256 votingPeriod = IPolicy(registry().registries("Policy"))
			.policyVotingBlocks();
		uint256 votingEndBlockNumber = block.number.add(votingPeriod);
		closeVoteAt[_addr] = votingEndBlockNumber;
	}

	function isDuringVotingPeriod(address _policy)
		public
		view
		override
		returns (bool)
	{
		return block.number < closeVoteAt[_policy];
	}
}
