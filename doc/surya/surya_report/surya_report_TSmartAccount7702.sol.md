## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ./TSmartAccount7702.sol | 270acff5e5df391762b703e987a7bb8452bc7c6b |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **TSmartAccount7702** | Implementation | ERC7739, SignerEIP7702, IAccount, Initializable |||
| └ | <Constructor> | Public ❗️ | 🛑  | EIP712 |
| └ | initialize | External ❗️ | 🛑  | initializer |
| └ | validateUserOp | External ❗️ | 🛑  | onlyEntryPoint |
| └ | execute | External ❗️ |  💵 | onlyEntryPointOrSelf |
| └ | deployDeterministic | External ❗️ |  💵 | onlyEntryPointOrSelf |
| └ | version | External ❗️ |   |NO❗️ |
| └ | entryPoint | Public ❗️ |   |NO❗️ |
| └ | _getEntryPointStorage | Private 🔐 |   | |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | onERC721Received | External ❗️ |   |NO❗️ |
| └ | onERC1155Received | External ❗️ |   |NO❗️ |
| └ | onERC1155BatchReceived | External ❗️ |   |NO❗️ |
| └ | _call | Internal 🔒 | 🛑  | |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | <Fallback> | External ❗️ |  💵 |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
