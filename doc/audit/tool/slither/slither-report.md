**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [assembly](#assembly) (5 results) (Informational)
## assembly
Impact: Informational
Confidence: High
 - [ ] ID-0
[SmartAccount7702._call(address,uint256,bytes)](src/SmartAccount7702.sol#L318-L331) uses assembly
	- [INLINE ASM](src/SmartAccount7702.sol#L322-L330)

src/SmartAccount7702.sol#L318-L331


 - [ ] ID-1
[SmartAccount7702.validateUserOp(PackedUserOperation,bytes32,uint256)](src/SmartAccount7702.sol#L131-L159) uses assembly
	- [INLINE ASM](src/SmartAccount7702.sol#L145-L147)

src/SmartAccount7702.sol#L131-L159


 - [ ] ID-2
[SmartAccount7702._getEntryPointStorage()](src/SmartAccount7702.sol#L262-L266) uses assembly
	- [INLINE ASM](src/SmartAccount7702.sol#L263-L265)

src/SmartAccount7702.sol#L262-L266


 - [ ] ID-3
[SmartAccount7702.deploy(uint256,bytes)](src/SmartAccount7702.sol#L197-L219) uses assembly
	- [INLINE ASM](src/SmartAccount7702.sol#L209-L217)

src/SmartAccount7702.sol#L197-L219


 - [ ] ID-4
[SmartAccount7702.deployDeterministic(uint256,bytes,bytes32)](src/SmartAccount7702.sol#L232-L254) uses assembly
	- [INLINE ASM](src/SmartAccount7702.sol#L244-L252)

src/SmartAccount7702.sol#L232-L254


