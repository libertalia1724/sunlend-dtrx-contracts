import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";
import "@layerzerolabs/hardhat-tron";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.24",
        settings: {
          evmVersion: "istanbul",
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },

  tronSolc: {
    enable: true,
    filter: [],
    compilers: [{ version: "0.8.24" }],
    versionRemapping: [
      ["0.8.35", "0.8.24"],
    ],
  },

  gasReporter: {
    enabled: true,
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: "gas-report.txt",
    noColors: true,
    token: "TRX",
    gasPrice: 100,
  },

  networks: {
    tronMainnet: {
      url: "https://api.trongrid.io/jsonrpc",
      accounts: [process.env.NILE_PRIVATE_KEY!],
      httpHeaders: {
        "TRON-PRO-API-KEY": process.env.TRONGRID_API_KEY!,
      },
      tron: true,
    },

    nile: {
      // TRON testnet
      url: "https://nile.trongrid.io/jsonrpc",
      accounts: [process.env.NILE_PRIVATE_KEY!],
      httpHeaders: {
        "TRON-PRO-API-KEY": process.env.TRONGRID_API_KEY!,
      },
      tron: true,
    },

    shasta: {
      // TRON testnet
      url: "https://api.shasta.trongrid.io/jsonrpc",
      accounts: [process.env.NILE_PRIVATE_KEY!],
      tron: true,
    },
  },

  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
};

export default config;