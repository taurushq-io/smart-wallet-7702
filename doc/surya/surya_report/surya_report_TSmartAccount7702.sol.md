## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ./TSmartAccount7702.sol | 6407a880f2907e7c693b664acc190d1a951cb96d |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **TSmartAccount7702** | Implementation | ERC7739, SignerEIP7702, IAccount |||
| └ | <Constructor> | Public ❗️ | 🛑  | EIP712 |
| └ | validateUserOp | External ❗️ | 🛑  | onlyEntryPoint |
| └ | execute | External ❗️ |  💵 | onlyEntryPointOrSelf |
| └ | deployDeterministic | External ❗️ |  💵 | onlyEntryPointOrSelf |
| └ | version | External ❗️ |   |NO❗️ |
| └ | entryPoint | Public ❗️ |   |NO❗️ |
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
