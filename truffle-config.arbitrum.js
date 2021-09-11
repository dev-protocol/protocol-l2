/* eslint-disable @typescript-eslint/no-var-requires */
require('ts-node/register')
require('dotenv').config()
const HDWalletProvider = require('@truffle/hdwallet-provider')
const { INFURA_KEY, MNEMONIC } = process.env

module.exports = {
	test_file_extension_regexp: /.*\.ts$/,
	contracts_build_directory: './build/arbitrum-contracts',
	compilers: {
		solc: {
			version: '0.8.6',
			settings: {
				optimizer: {
					enabled: true,
				},
			},
		},
	},

	networks: {
		arbitrum_local: {
			network_id: '*',
			gas: 8500000,
			provider: function () {
				return new HDWalletProvider({
					mnemonic: {
						phrase: MNEMONIC,
					},
					providerOrUrl: 'http://127.0.0.1:8547/',
					addressIndex: 0,
					numberOfAddresses: 1,
				})
			},
		},
		arbitrum_testnet: {
			network_id: 421611,
			provider: function () {
				return new HDWalletProvider({
					mnemonic: {
						phrase: MNEMONIC,
					},
					providerOrUrl: 'https://arbitrum-rinkeby.infura.io/v3/' + INFURA_KEY,
					addressIndex: 0,
					numberOfAddresses: 1,
					network_id: 421611,
					chainId: 421611,
				})
			},
		},
		arbitrum_mainnet: {
			network_id: 42161,
			chain_id: 42161,
			provider: function () {
				return new HDWalletProvider(
					MNEMONIC,
					'https://arbitrum-mainnet.infura.io/v3/' + INFURA_KEY,
					0,
					1
				)
			},
		},
	},

	mocha: {
		timeout: 100000,
	},
	db: {
		enabled: false,
	},
}
