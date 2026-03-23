**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [assembly](#assembly) (4 results) (Informational)
## assembly
Impact: Informational
Confidence: High
 - [ ] ID-0
[TSmartAccount7702._getEntryPointStorage()](src/TSmartAccount7702.sol#L236-L240) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L237-L239)

src/TSmartAccount7702.sol#L236-L240


 - [ ] ID-1
[TSmartAccount7702._call(address,uint256,bytes)](src/TSmartAccount7702.sol#L292-L305) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L296-L304)

src/TSmartAccount7702.sol#L292-L305


 - [ ] ID-2
[TSmartAccount7702.validateUserOp(PackedUserOperation,bytes32,uint256)](src/TSmartAccount7702.sol#L139-L167) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L153-L155)

src/TSmartAccount7702.sol#L139-L167


 - [ ] ID-3
[TSmartAccount7702.deployDeterministic(uint256,bytes,bytes32)](src/TSmartAccount7702.sol#L201-L223) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L213-L221)

src/TSmartAccount7702.sol#L201-L223


