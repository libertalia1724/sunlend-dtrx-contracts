# SunLend fTRX Contracts

Solidity implementation of the Sunlend's liquid staking token fTRX contracts.

## Dependencies

- [TronBox](https://tronbox.io/docs/guides/installation) - Development Framework for TRON Network
- [TronWeb](https://tronweb.network/docu/docs/intro) - JavaScript Library for Interacting TRON Network
- [Dotenv](https://www.dotenv.org) - to Manage Environment Variables
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts) - Library for Developing Smart Contracts

## Setup

- Download **Node.js** from this [site](https://nodejs.org/en/download).

- Verify **Node.js** installation.

```bash
  node --version
  npm --version
```

- Download **Docker Desktop** from this [site](https://www.docker.com/products/docker-desktop).

- If you are using **WSL 2** enable **WSL Integration**:

1. **Settings** > **Resources** > **WSL integration** 

2. Check this box: **Enable integration with my default WSL distro**

3. **Apply** the changes.

- Verify **Docker Desktop** installation.

```bash
  docker --version
  docker run hello-world
```

- Install **TRE - TronBox Runtime Environment**

> *Information: TRE is a local TRON network for testing, debugging and deploying smart contracts.*

```bash
  docker pull tronbox/tre
```

- Clone this repository

```bash
  git clone https://github.com/sunlend/sunlend-ftrx-contracts
  cd sunlend-ftrx-contracts
```

- Create environment variables

1. Rename ```.env.example``` file to ```.env```.

2. Add private keys for **TRON Mainnet**, **Nile Testnet** and **Shasta Testnet** on ```.env``` file.

> *NEVER COMMIT ```.env``` FILE*

- Configure **VS Code** **Solidity** extension

1. If you are using **Juan Blanco**'s **Solidity** [extension](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) follow this steps.

2. Run commands.

```bash
  mkdir .vscode
  cd .vscode
  mkdir tron-solc
  mv settings.example.json settings.json
  curl -L -o tron-solc/soljson-v<SOLIDITY_VERSION>.js https://raw.githubusercontent.com/tronprotocol/solc-bin/main/wasm/soljson-<SOLIDITY_VERSION>+commit.<SOLIDITY_VERSION_COMMIT>.js
  realpath soljson-v<SOLIDITY_VERSION>.js
```

3. Add ```realpath``` output for value of ```"solidity.compileUsingLocalVersion"``` key.

4. Reload **VS Code** window.

- Run **TRE**

```bash
  docker run -it -p 9090:9090 --rm --name tron -e "useDefaultPrivateKey=true" tronbox/tre
```

and run stopping **TRE**:

```bash
  docker stop tron
```

## Deployment

- **TRON Mainnet**

```bash
  tronbox migrate --network mainnet
```

- **Nile Testnet**

```bash
  tronbox migrate --network nile
```

- **Shasta Testnet**

```bash
  tronbox migrate --network shasta
```

- **TronBox Runtime Environment**

```bash
  tronbox migrate --network development
```

## Testing

```bash
  tronbox test --network <mainnet|shasta|nile|development>
```