pragma solidity ^0.5.0;

import "./BlockRelay.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";


/**
 * @title Witnet Bridge Interface
 * @notice Contract to bridge requests to Witnet
 * @dev This contract enables posting requests that Witnet bridges will insert into the Witnet network
  * The result of the requests will be posted back to this contract by the bridge nodes too.
 * @author Witnet Foundation
 */
contract WitnetBridgeInterface {

  using SafeMath for uint256;

  struct DataRequest {
    bytes dr;
    uint256 inclusionReward;
    uint256 tallyReward;
    bytes result;
    uint256 timestamp;
    uint256 drHash;
    address payable pkhClaim;
  }

  BlockRelay blockRelay;

  mapping (uint256 => DataRequest) public requests;

  // Event emitted when a new DR is posted
  event PostedRequest(address indexed _from, uint256 _id);
  // Event emitted when a DR inclusion proof is posted
  event IncludedRequest(address indexed _from, uint256 _id);
  // Event emitted when a result proof is posted
  event PostedResult(address indexed _from, uint256 _id);

  // Ensures the reward is not greater than the value
  modifier payingEnough(uint256 _value, uint256 _tally) {
    require(_value >= _tally, "Transaction value needs to be equal or greater than tally reward");
    _;
  }
  // Ensures the proof of eligibility is valid
  modifier poeValid(bytes memory _poe) {
    require(verifyPoe(_poe) == true, "Not a valid PoE");
    _;
  }
  // Ensures the DR inclusion proof has not been reported yet
  modifier drNotIncluded(uint256 _id) {
    require(requests[_id].drHash == 0, "DR already included");
    _;
  }
  // Ensures the DR inclusion has been already reported
  modifier drIncluded(uint256 _id) {
    require(requests[_id].drHash != 0, "DR not yet included");
    _;
  }
  // Ensures the result has not been reported yet
  modifier resultNotIncluded(uint256 _id) {
    require(requests[_id].result.length == 0, "Result already included");
    _;
  }

  constructor (address _blockRelayAddress) public {
    blockRelay = BlockRelay(_blockRelayAddress);
  }

  /// @dev Posts a data request into the WBI in expectation that it will be relayed and resolved in Witnet with a total reward that equals to msg.value.
  /// @param _dr The bytes corresponding to the Protocol Buffers serialization of the data request output.
  /// @param _tallyReward The amount of value that will be detracted from the transaction value and reserved for rewarding the reporting of the final result (aka tally) of the data request.
  /// @return The unique identifier of the data request.
  function postDataRequest(bytes memory _dr, uint256 _tallyReward)
    public
    payable
    payingEnough(msg.value, _tallyReward)
  returns(uint256 _id) {
    _id = uint256(sha256(_dr));
    if(requests[_id].dr.length != 0) {
      requests[_id].tallyReward += _tallyReward;
      requests[_id].inclusionReward += msg.value - _tallyReward;
      return _id;
    }

    requests[_id].dr = _dr;
    requests[_id].inclusionReward = msg.value - _tallyReward;
    requests[_id].tallyReward = _tallyReward;
    requests[_id].result = "";
    requests[_id].timestamp = 0;
    requests[_id].drHash = 0;
    requests[_id].pkhClaim = address(0);
    emit PostedRequest(msg.sender, _id);
    return _id;
  }

  /// @dev Increments the rewards of a data request by adding more value to it. The new request reward will be increased by msg.value minus the difference between the former tally reward and the new tally reward.
  /// @param _id The unique identifier of the data request.
  /// @param _tallyReward The new tally reward. Needs to be equal or greater than the former tally reward.
  function upgradeDataRequest(uint256 _id, uint256 _tallyReward)
    public
    payable
    payingEnough(msg.value, _tallyReward)
  {
    requests[_id].inclusionReward += msg.value - _tallyReward;
    requests[_id].tallyReward += _tallyReward;
  }

  /// @dev Claims eligibility for relaying the data requests specified by the listed IDs and puts aside the potential data request inclusion reward for the identity (public key hash) making the claim.
  /// @param _ids The list of data request identifiers to be claimed.
  /// @param _poe A valid proof of eligibility generated by the bridge node that is claiming the data requests.
  function claimDataRequests(uint256[] memory _ids, bytes memory _poe)
    public
    poeValid(_poe)
  {
    uint256 currentEpoch = block.number;
    uint256 index;
    for (uint i = 0; i < _ids.length; i++) {
      index = _ids[i];
      if((requests[index].timestamp == 0 || currentEpoch-requests[index].timestamp > 13) &&
      requests[index].drHash == 0 &&
      requests[index].result.length == 0){
        requests[index].pkhClaim = msg.sender;
        requests[index].timestamp = currentEpoch;
      }
      else{
        revert("One of the listed data requests was already claimed");
      }
    }
  }

  /// @dev Presents a proof of inclusion to prove that the request was posted into Witnet so as to unlock the inclusion reward that was put aside for the claiming identity (public key hash).
  /// @param _id The unique identifier of the data request.
  /// @param _poi A proof of inclusion proving that the data request appears listed in one recent block in Witnet.
  /// @param _index The index in the merkle tree.
  /// @param _blockHash The hash of the block in which the data request was inserted.
  function reportDataRequestInclusion (
    uint256 _id,
    uint256[] memory _poi,
    uint256 _index,
    uint256 _blockHash
    )
    public
    drNotIncluded(_id)
 {
    uint256 drRoot = blockRelay.readDrMerkleRoot(_blockHash);
    uint256 drHash = uint256(sha256(abi.encodePacked(_id, _poi[0])));
    if (verifyPoi(_poi, drRoot, _index, _id)) {
      requests[_id].drHash = drHash;
      requests[_id].pkhClaim.transfer(requests[_id].inclusionReward);
      emit IncludedRequest(msg.sender, _id);
    } else {
      revert("Invalid PoI");
    }
  }

  /// @dev Reports the result of a data request in Witnet.
  /// @param _id The unique identifier of the data request.
  /// @param _poi A proof of inclusion proving that the data in _result has been acknowledged by the Witnet network as being the final result for the data request by putting in a tally transaction inside a Witnet block.
  /// @param _index The position of the tally transaction in the tallies-only merkle tree in the Witnet block.
  /// @param _blockHash The hash of the block in which the result (tally) was inserted.
  /// @param _result The result itself as bytes.
  function reportResult (
    uint256 _id,
    uint256[] memory _poi,
    uint256 _index,
    uint256 _blockHash,
    bytes memory _result
    )
    public
    drIncluded(_id)
    resultNotIncluded(_id)
 {
    uint256 tallyRoot = blockRelay.readTallyMerkleRoot(_blockHash);
    // this should leave it ready for PoI
    uint256 resHash = uint256(sha256(abi.encodePacked(requests[_id].drHash, _result)));
    if (verifyPoi(_poi, tallyRoot, _index, resHash)){
      requests[_id].result = _result;
      msg.sender.transfer(requests[_id].tallyReward);
      emit PostedResult(msg.sender, _id);
    }
    else{
      revert("Invalid PoI");
    }
  }

  /// @dev Retrieves the bytes of the serialization of one data request from the WBI.
  /// @param _id The unique identifier of the data request.
  /// @return The result of the data request as bytes.
  function readDataRequest (uint256 _id) public view returns(bytes memory){
    return requests[_id].dr;
  }

  /// @dev Retrieves the result (if already available) of one data request from the WBI.
  /// @param _id The unique identifier of the data request.
  /// @return The result of the DR
  function readResult (uint256 _id) public view returns(bytes memory){
    return requests[_id].result;
  }

  /// @dev Retrieves hash of the data request transaction in Witnet
  /// @param _id The unique identifier of the data request.
  /// @return The hash of the DataRequest transaction in Witnet
  function readDrHash (uint256 _id) public view returns(uint256){
    return requests[_id].drHash;
  }

  function verifyPoe(bytes memory _poe) internal pure returns(bool){
    return true;
  }

  /// @dev Verifies the validity of a PoI
  /// @param _poi the proof of inclusion as [leaf1, leaf2,..]
  /// @param _root the merkle root
  /// @param _index the index in the merkle tree of the element to verify
  /// @param _element the element
  /// @return true or false depending the validity
  function verifyPoi(
    uint256[] memory _poi,
    uint256 _root,
    uint256 _index,
    uint256 _element)
  public pure returns(bool){
    uint256 tree = _element;
    uint256 index = _index;
    for (uint i = 0; i<_poi.length; i++){
      if(index%2 == 0){
        tree = uint256(sha256(abi.encodePacked(tree, _poi[i])));
      }
      else{
        tree = uint256(sha256(abi.encodePacked(_poi[i], tree)));
      }
      index = index>>1;
    }
    return _root==tree;
  }
}
