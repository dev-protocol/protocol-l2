// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UsingRegistry} from "contracts/src/common/registry/UsingRegistry.sol";
import {IMarketBehavior} from "contracts/interface/IMarketBehavior.sol";
import {IMarket} from "contracts/interface/IMarket.sol";

contract MarketTest3 is Ownable, IMarketBehavior, UsingRegistry {
	string public override schema = "[]";
	address private associatedMarket;
	mapping(address => string) internal keys;
	mapping(string => address) private addresses;
	address public currentAuthinticateAccount;

	constructor(address _registry) UsingRegistry(_registry) {}

	function authenticate(
		address _prop,
		string memory _args1,
		string memory,
		string memory,
		string memory,
		string memory,
		address market,
		address account
	) external override returns (bool) {
		require(msg.sender == associatedMarket, "Invalid sender");

		bytes32 idHash = keccak256(abi.encodePacked(_args1));
		address _metrics = IMarket(market).authenticatedCallback(_prop, idHash);
		keys[_metrics] = _args1;
		addresses[_args1] = _metrics;
		currentAuthinticateAccount = account;
		return true;
	}

	function getId(address _metrics)
		external
		view
		override
		returns (string memory)
	{
		return keys[_metrics];
	}

	function getMetrics(string calldata _id)
		external
		view
		override
		returns (address)
	{
		return addresses[_id];
	}

	function setAssociatedMarket(address _associatedMarket) external onlyOwner {
		associatedMarket = _associatedMarket;
	}
}
