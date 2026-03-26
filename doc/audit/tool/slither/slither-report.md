**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [assembly](#assembly) (3 results) (Informational)
 - [naming-convention](#naming-convention) (1 results) (Informational)
## assembly
Impact: Informational
Confidence: High
 - [ ] ID-0
[TSmartAccount7702._call(address,uint256,bytes)](src/TSmartAccount7702.sol#L267-L280) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L271-L279)

src/TSmartAccount7702.sol#L267-L280


 - [ ] ID-1
[TSmartAccount7702.validateUserOp(PackedUserOperation,bytes32,uint256)](src/TSmartAccount7702.sol#L108-L145) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L139-L141)

src/TSmartAccount7702.sol#L108-L145


 - [ ] ID-2
[TSmartAccount7702.deployDeterministic(uint256,bytes,bytes32)](src/TSmartAccount7702.sol#L174-L196) uses assembly
	- [INLINE ASM](src/TSmartAccount7702.sol#L186-L194)

src/TSmartAccount7702.sol#L174-L196


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-3
Variable [TSmartAccount7702.ENTRY_POINT](src/TSmartAccount7702.sol#L49) is not in mixedCase

src/TSmartAccount7702.sol#L49


