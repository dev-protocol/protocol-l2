/* solhint-disable const-name-snakecase */
/* solhint-disable var-name-mixedcase */
// SPDX-License-Identifier: MPL-2.0
pragma solidity =0.8.6;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UsingRegistry} from "contracts/src/common/registry/UsingRegistry.sol";
import {IPolicy} from "contracts/interface/IPolicy.sol";
import {Curve} from "contracts/src/common/libs/Curve.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Policy1 is IPolicy, Ownable, Curve, UsingRegistry {
	using SafeMath for uint256;
	uint256 public override marketVotingBlocks = 525600;
	uint256 public override policyVotingBlocks = 525600;
	address private treasuryAddress;
	address private capSetterAddress;

	uint256 private constant basis = 10000000000000000000000000;
	uint256 private constant power_basis = 10000000000;
	uint256 private constant mint_per_block_and_aseet = 132000000000000;

	constructor(address _registry) UsingRegistry(_registry) {}

	function rewards(uint256 _lockups, uint256 _assets)
		external
		view
		virtual
		override
		returns (uint256)
	{
		uint256 totalSupply = IERC20(registry().registries("Dev"))
			.totalSupply();
		return
			curveRewards(
				_lockups,
				_assets,
				totalSupply,
				mint_per_block_and_aseet
			);
	}

	function holdersShare(uint256 _reward, uint256 _lockups)
		external
		view
		virtual
		override
		returns (uint256)
	{
		return _lockups > 0 ? (_reward.mul(51)).div(100) : _reward;
	}

	function authenticationFee(uint256 total_assets, uint256 property_lockups)
		external
		view
		virtual
		override
		returns (uint256)
	{
		uint256 a = total_assets.div(10000);
		uint256 b = property_lockups.div(100000000000000000000000);
		if (a <= b) {
			return 0;
		}
		return a.sub(b);
	}

	function shareOfTreasury(uint256 _supply)
		external
		pure
		override
		returns (uint256)
	{
		return _supply.div(100).mul(5);
	}

	function treasury() external view override returns (address) {
		return treasuryAddress;
	}

	function setTreasury(address _treasury) external onlyOwner {
		treasuryAddress = _treasury;
	}

	function capSetter() external view virtual override returns (address) {
		return capSetterAddress;
	}

	function setCapSetter(address _setter) external onlyOwner {
		capSetterAddress = _setter;
	}
}
