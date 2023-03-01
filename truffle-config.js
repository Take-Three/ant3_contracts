const HDWalletProvider = require('@truffle/hdwallet-provider');
const { mnemonic, bscScanKey } = require("./secrets.json");
const bscMainnetUrl = `wss://bsc-ws-node.nariox.org:443`;
const anisticUrl = `https://mainnet-rpc.anisticnetwork.com`;
const anisticTestnetUrl = `https://testnet-rpc.anisticnetwork.net`;
const bscTestnetUrl = `https://data-seed-prebsc-1-s3.binance.org:8545`;
const Web3 = require("web3");
const web3 = new Web3();

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*",
    },
    bsc: {
      provider: () => new HDWalletProvider(mnemonic, bscMainnetUrl),
      network_id: 56,
      // gas: 5000000,
      // gasPrice: web3.utils.toWei('2', 'gwei'),
      confirmations: 0,
      timeoutBlocks: 50,
      networkCheckTimeout: 1000000,
      skipDryRun: true,
    },
    ant: {
      provider: () => new HDWalletProvider(mnemonic, anisticUrl),
      network_id: "6188",
      gas: 5000000,
      gasPrice: web3.utils.toWei('30', 'gwei'),
      confirmations: 0,
      timeoutBlocks: 50,
      networkCheckTimeout: 1000000,
      skipDryRun: true,
    },
    anisticTest: {
      provider: () => new HDWalletProvider(mnemonic, anisticTestnetUrl),
      network_id: 6181,
      gas: 5000000,
      gasPrice: web3.utils.toWei('30', 'gwei'),
      confirmations: 0,
      timeoutBlocks: 50,
      networkCheckTimeout: 1000000,
      skipDryRun: true,
    },
    bscTest: {
      provider: () => new HDWalletProvider(mnemonic, bscTestnetUrl),
      network_id: 97,
      // gas: 5000000,
      // gasPrice: web3.utils.toWei('2', 'gwei'),
      confirmations: 0,
      timeoutBlocks: 50,
      networkCheckTimeout: 1000000,
      skipDryRun: true,
    },
  },
  compilers: {
    solc: {
      version: "0.8.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  },
  plugins: ['truffle-plugin-verify',
    'truffle-plugin-stdjsonin'
  ],

  api_keys: {
    bscscan: bscScanKey,
  }
}