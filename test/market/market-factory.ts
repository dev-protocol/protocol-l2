import { DevProtocolInstance } from '../test-lib/instance'
import { getMarketAddress } from '../test-lib/utils/log'
import {
	validateAddressErrorMessage,
	validateErrorMessage,
} from '../test-lib/utils/error'
import { DEFAULT_ADDRESS } from '../test-lib/const'

contract('MarketFactoryTest', ([deployer, user, dummyMarketAddress]) => {
	const marketContract = artifacts.require('Market')
	const init = async (): Promise<
		[DevProtocolInstance, string, string, [string, string]]
	> => {
		const dev = new DevProtocolInstance(deployer)
		await dev.generateAddressRegistry()
		await Promise.all([
			dev.generatePolicyFactory(),
			dev.generateMarketFactory(),
			dev.generateLockup(false),
			dev.generateMetricsFactory(),
		])
		const policy = await dev.getPolicy('PolicyTest1', user)
		await dev.policyFactory.create(policy.address, { from: user })
		const market = await dev.getMarket('MarketTest1', user)
		const marketBehaviorAddress = market.address
		const result = await dev.marketFactory.create(market.address, {
			from: user,
		})
		const eventFrom = result.logs.filter(
			(log: { event: string }) => log.event === 'Create'
		)[0].args._from as string
		const eventMarket = result.logs.filter(
			(log: { event: string }) => log.event === 'Create'
		)[0].args._market as string
		const marketAddress = getMarketAddress(result)
		return [dev, marketAddress, marketBehaviorAddress, [eventMarket, eventFrom]]
	}

	describe('MarketFactory; create', () => {
		it('Create a new market contract and emit create event telling created market address,', async () => {
			const [, market, marketBehavior] = await init()

			const deployedMarket = await marketContract.at(market)
			const behaviorAddress = await deployedMarket.behavior({ from: deployer })
			expect(behaviorAddress).to.be.equal(marketBehavior)
		})
		it('A freshly created market is enabled,', async () => {
			const [, market] = await init()

			const deployedMarket = await marketContract.at(market)
			expect(await deployedMarket.enabled()).to.be.equal(true)
		})
		it('A secoundly created market is not enabled,', async () => {
			const [, market] = await init()

			const deployedMarket = await marketContract.at(market)
			expect(await deployedMarket.enabled()).to.be.equal(true)
		})
		it('generate create event', async () => {
			const [, market, , [marketAddress, fromAddress]] = await init()
			expect(fromAddress).to.be.equal(user)
			expect(marketAddress).to.be.equal(market)
		})
		it('The second and subsequent markets will not be automatically enabled.', async () => {
			const [dev] = await init()
			const secoundMarket = await dev.getMarket('MarketTest1', user)
			const result = await dev.marketFactory.create(secoundMarket.address, {
				from: user,
			})
			const secoundMarketAddress = getMarketAddress(result)

			const deployedMarket = await marketContract.at(secoundMarketAddress)
			expect(await deployedMarket.enabled()).to.be.equal(false)
		})
		it('An error occurs if the default address is specified.', async () => {
			const [dev] = await init()
			const result = await dev.marketFactory
				.create(DEFAULT_ADDRESS, {
					from: user,
				})
				.catch((err: Error) => err)
			validateAddressErrorMessage(result)
		})
	})

	describe('MarketFactory; enable', () => {
		describe('failed', () => {
			it('Cannot be executed by anyone but the owner.', async () => {
				const dev = new DevProtocolInstance(deployer)
				await dev.generateAddressRegistry()
				await dev.generateMarketFactory()
				const res = await dev.marketFactory
					.enable(DEFAULT_ADDRESS, {
						from: user,
					})
					.catch((err: Error) => err)
				validateErrorMessage(res, 'caller is not the owner', false)
			})
			it('Only the market address can be specified.', async () => {
				const dev = new DevProtocolInstance(deployer)
				await dev.generateAddressRegistry()
				await dev.generateMarketFactory()
				const res = await dev.marketFactory
					.enable(dummyMarketAddress)
					.catch((err: Error) => err)
				validateAddressErrorMessage(res)
			})
			it('we cannot specify the address of an active market.', async () => {
				const [dev, market] = await init()
				const res = await dev.marketFactory
					.enable(market)
					.catch((err: Error) => err)
				validateErrorMessage(res, 'already enabled')
			})
		})
		describe('success', () => {
			it('Enabling the Market', async () => {
				const [dev] = await init()
				const secoundMarket = await dev.getMarket('MarketTest1', user)
				const result = await dev.marketFactory.create(secoundMarket.address, {
					from: user,
				})
				const secoundMarketAddress = getMarketAddress(result)
				await dev.marketFactory.enable(secoundMarketAddress)

				const deployedMarket = await marketContract.at(secoundMarketAddress)
				expect(await deployedMarket.enabled()).to.be.equal(true)
			})
		})
	})

	describe('MarketFactory; isMarket', () => {
		it('Returns true when the passed address is the created Market', async () => {
			const [dev, market] = await init()
			const result = await dev.marketFactory.isMarket(market)
			expect(result).to.be.equal(true)
		})
		it('Returns false when the passed address is not the created Market', async () => {
			const [dev] = await init()
			const result = await dev.marketFactory.isMarket(deployer)
			expect(result).to.be.equal(false)
		})
	})

	describe('MarketFactory; getEnabledMarkets', () => {
		it('get market address list', async () => {
			const [dev, marketAddress] = await init()
			const result = await dev.marketFactory.getEnabledMarkets()
			expect(result.length).to.be.equal(1)
			expect(result[0]).to.be.equal(marketAddress)
		})
		it('add market address list', async () => {
			const [dev, marketAddress] = await init()
			const market = await dev.getMarket('MarketTest2', user)
			const result = await dev.marketFactory.create(market.address, {
				from: user,
			})
			const marketAddress2 = getMarketAddress(result)
			await dev.marketFactory.enable(marketAddress2)
			const markets = await dev.marketFactory.getEnabledMarkets()
			expect(markets.length).to.be.equal(2)
			expect(markets[0]).to.be.equal(marketAddress)
			expect(markets[1]).to.be.equal(marketAddress2)
		})
	})

	describe('MarketFactory; marketsCount', () => {
		it('Returns the number of enabled Markets', async () => {
			const [dev] = await init()
			const result = await dev.marketFactory.marketsCount()
			expect(result.toNumber()).to.be.equal(1)
		})
		it('Should be increased the number when a new Market is enabled', async () => {
			const [dev] = await init()
			const behavior = await dev.getMarket('MarketTest3', user)
			const created = await dev.marketFactory.create(behavior.address)
			const secoundMarketAddress = getMarketAddress(created)
			await dev.marketFactory.enable(secoundMarketAddress)
			const result = await dev.marketFactory.marketsCount()
			expect(result.toNumber()).to.be.equal(2)
		})
	})
})
