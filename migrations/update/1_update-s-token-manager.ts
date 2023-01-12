import { upgradeProxy } from '@openzeppelin/truffle-upgrades'
import { type ContractClass } from '@openzeppelin/truffle-upgrades/dist/utils'

const handler = async function (_, network) {
	if (network === 'test') {
		return
	}

	const adminAddress = process.env.ADMIN!
	const proxyAddress = process.env.S_TOKEN_MANAGER_PROXY!
	console.log('Admin address:', adminAddress)
	console.log('STokensManager proxy address:', proxyAddress)

	await upgradeProxy(
		proxyAddress,
		artifacts.require('STokensManager') as unknown as ContractClass
	)
	console.log(
		'New implementation:',
		await artifacts
			.require('DevAdmin')
			.at(adminAddress)
			.getProxyImplementation(proxyAddress)
	)
} as Truffle.Migration

export = handler
