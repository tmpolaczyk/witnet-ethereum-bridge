# witnet-ethereum-bridge [![](https://travis-ci.com/witnet/witnet-ethereum-bridge.svg?branch=master)](https://travis-ci.com/witnet/witnet-ethereum-brdige)

`witnet-ethereum-bridge` is an open source implementation of a bridge 
from Ethereum to Witnet. This repository provides several contracts:

- The `Witnet Bridge Interface`(WBI), which includes all the needed 
functionality to relay data requests and their results from Ethereum to Witnet and the other way round.
- `UsingWitnet`, an inheritable client contract that injects methods for interacting with the WBI in the most convenient way.
- `BlockRelay`, a contract that incentivizes secure relaying of Witnet blocks into Ethereum so that Witnet transactions can be verified by the EVM.

The `WitnetBridgeInterface` contract provides the following methods:

- **postDataRequest**:
  - _description_: posts a data request into the WBI in expectation that it will be relayed and resolved 
  in Witnet with a total reward that equals to msg.value.
  - _inputs_:
    - *_dr*: the bytes corresponding to the Protocol Buffers serialization of the data request output.
    - *_tallyReward*: the amount of value that will be detracted from the transaction value and reserved for rewarding the reporting of the final result (aka __tally__) of the data request.
  - output:
    - *_id*: the unique identifier of the data request.

- **upgradeDataRequest**:
  - *description*: increments the rewards of a data request by 
  adding more value to it. The new request reward will be increased by `msg.value` minus the difference between the former tally reward and the new tally reward.
  - *_inputs*:
    - *_id*: the unique identifier of the data request.
    - *_tallyReward*: the new tally reward. Needs to be equal or greater than the former tally reward.

- **claimDataRequests**:
  - _description_: claims eligibility for relaying the data requests specified by the listed IDs
   and puts aside the potential data request inclusion reward for the 
   identity (public key hash) making the claim.
  - _inputs_:
    - *_ids*: the list of data request identifiers to be claimed.
    - *_poe*: a valid proof of eligibility generated by the bridge node that is claiming the
    data requests.

- **reportDataRequestInclusion**:
  - _description_: presents a proof of inclusion to prove that the request was posted into Witnet so as to unlock the 
  inclusion reward that was put aside for the claiming identity (public key hash).
  - _inputs_:
    - *_id*: the unique identifier of the data request.
    - *_poi*: a proof of inclusion proving that the data request appears listed in one recent block 
    in Witnet.
    - *_index*: index in the merkle tree.
    - *_blockHash*: the hash of the block in which the data request 
    was inserted.
- **reportResult**:
  - _description_: reports the result of a data request in Witnet.
  - _inputs_:
    - *_id*: the unique identifier of the data request.
    - *_poi*: a proof of inclusion proving that the data in `_result` has been acknowledged by the Witnet network as being the final result for the data request by putting in a tally transaction inside a Witnet block.
    - *_index*: the position of the tally transaction in the tallies-only merkle tree in the Witnet block.
    - *_blockHash*: the hash of the block in which the result (tally) 
    was inserted.
    - *_result*: the result itself as `bytes`.
- **readDataRequest**:
  - _description_: retrieves the bytes of the serialization of one data request from the WBI.
  - _inputs_:
    - *_id*: the unique identifier of the data request.
  - _output_:
    - the data request bytes.
- **readResult**:
  - _description_: retrieves the result (if already available) of one data request from the WBI.
  - _inputs_:
    - *_id*: the unique identifier of the data request.
  - _output_:
    - the result of the data request as `bytes`.

The `BlockRelay` contract has the following methods:

- **postNewBlock**:
  - _description_: post a new block into the block relay.
  - _inputs_:
    - *_blockHash*: Hash of the block header.
    - *_drMerkleRoot*: the root hash of the requests-only merkle tree as contained in the block header.
    - *_tallyMerkleRoot*: the root hash of the tallies-only merkle tree as contained in the block header.
- **readDrMerkleRoot**:
  - _description_: retrieve the requests-only merkle root hash that was reported for a specific block header.
  - _inputs_:
    - *_blockHash*: hash of the block header.
  - _output_:
    - requests-only merkle root hash in the block header.
- **readTallyMerkleRoot**:
  - _description_: retrieve the tallies-only merkle root hash that was reported for a specific block header.
  - _inputs_:
    - *_blockHash*: hash of the block header.
  - _output_:
    - tallies-only merkle root hash in the block header.
  
The `UsingWitnet` contract injects the following methods into the contracts inheriting from it:

- **witnetPostDataRequest**:
  - _description_: call to the WBI's `postDataRequest` method to post a 
  data request into the WBI so its is resolved in Witnet with total reward 
  specified in `msg.value`.
  - _inputs_:
    - *_dr*: the bytes corresponding to the Protocol Buffers serialization of the data request output.
    - *_tallyReward*: the amount of value that will be detracted from the transaction value and reserved for rewarding the reporting of the final result (aka __tally__) of the data request.
     that is destinated to reward the result inclusion.
  - _output_:
    - *_id*: the unique identifier of the data request.

- **witnetUpgradeDataRequest**:
  - _description_: call to the WBI's `upgradeDataRequest` method to increment 
  the total reward of the data request by adding more value to it. The new request reward will be increased by `msg.value` minus the difference between the former tally reward and the new tally reward.
  - _inputs_:
    - *_id*: the unique identifier of the data request.
    - *_tallyReward*: the new tally reward. Needs to be equal or greater than the former tally reward.

- **witnetReadResult**:
  - _description_: call to the WBI's `readResult` method to retrieve
   the result of one data request from the WBI.
  - _inputs_:
    - *_id*: the unique identifier of the data request.
  - _output_:
    - the result of the data request as `bytes`.

## Known limitations:

- `block relay` is centralized at the moment (only the deployer of the contract is able to push blocks). In the future incentives will be established to decentralize block header reporting.
- `verify_poe` is still empty. Proof of eligibility verification trough VRF should be implemented.

## Usage

The `UsingWitnet.sol` contract can be used directly by inheritance or by instantiating it:

```solidity
pragma solidity ^0.5.0;

import "./UsingWitnet.sol";

contract Example is UsingWitnet {

  uint256 drCost = 10;
  uint256 tallyReward = 5;
  bytes memory dr = /* Here goes the data request serialized bytes. */;

  function myOwnDrPost() public returns(uint256 id) {
    id =  witnetPostDataRequest.value(drCost)(dr, tallyReward);
  }
}
```

## License

`witnet-ethereum-bridge` is published under the [MIT license][license].

[license]: https://github.com/witnet/witnet-ethereum-bridge/blob/master/LICENSE
