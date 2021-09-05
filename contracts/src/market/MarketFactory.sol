// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UsingRegistry} from "contracts/src/common/registry/UsingRegistry.sol";
import {Market} from "contracts/src/market/Market.sol";
import {IMarket} from "contracts/interface/IMarket.sol";
import {IMarketFactory} from "contracts/interface/IMarketFactory.sol";
import {IMarketGroup} from "contracts/interface/IMarketGroup.sol";

/**
 * A factory contract that creates a new Market contract.
 */
contract MarketFactory is Ownable, IMarketFactory, UsingRegistry {
	event Create(address indexed _from, address _market);

	/**
	 * Initialize the passed address as AddressRegistry address.
	 */
	constructor(address _registry) UsingRegistry(_registry) {}

	/**
	 * Creates a new Market contract.
	 */
	function create(address _addr) external override returns (address) {
		/**
		 * Validates the passed address is not 0 address.
		 */
		require(_addr != address(0), "this is illegal address");

		/**
		 * Creates a new Market contract with the passed address as the IMarketBehavior.
		 */
		Market market = new Market(address(registry()), _addr);

		/**
		 * Adds the created Market contract to the Market address set.
		 */
		address marketAddr = address(market);
		IMarketGroup marketGroup = IMarketGroup(
			registry().registries("MarketGroup")
		);
		marketGroup.addGroup(marketAddr);

		/**
		 * For the first Market contract, it will be activated immediately.
		 * If not, the Market contract will be activated after a vote by the voters.
		 */
		if (marketGroup.getCount() == 1) {
			market.toEnable();
		}

		emit Create(msg.sender, marketAddr);
		return marketAddr;
	}

	/**
	 * Creates a new Market contract.
	 */
	function enable(address _addr) external override onlyOwner {
		/**
		 * Validates the passed address is not 0 address.
		 */
		IMarketGroup marketGroup = IMarketGroup(
			registry().registries("MarketGroup")
		);
		require(marketGroup.isGroup(_addr), "this is illegal address");

		/**
		 * Market will be enable.
		 */
		IMarket market = IMarket(_addr);
		require(market.enabled() == false, "already enabled");

		market.toEnable();
	}
}
