pragma solidity ^0.5.0;

/**
 * @title Block relay contract
 * @notice Contract to store/read block headers from the Witnet network
 * @author Witnet Foundation
 */
contract BlockRelay {

  struct MerkleRoots {
    // hash of the merkle root of the DRs in Witnet
    uint256 drHashMerkleRoot;
    // hash of the merkle root of the tallies in Witnet
    uint256 tallyHashMerkleRoot;
  }
  // Address of the block pusher
  address witnet;

  mapping (uint256 => MerkleRoots) public blocks;

  // Event emitted when a new block is posted to the contract
  event NewBlock(address indexed _from, uint256 _id);

  constructor() public{
    // Only the contract deployer is able to push blocks
    witnet = msg.sender;
  }

  // Only the owner should be able to push blocks
  modifier isOwner() {
    require(msg.sender == witnet, "Sender not authorized"); // If it is incorrect here, it reverts.
    _; // Otherwise, it continues.
  }
  // Ensures block exists
  modifier blockExists(uint256 _id){
    require(blocks[_id].drHashMerkleRoot!=0, "Non-existing block");
    _;
  }
   // Ensures block does not exist
  modifier blockDoesNotExist(uint256 _id){
    require(blocks[_id].drHashMerkleRoot==0, "The block already existed");
    _;
  }

  /// @dev Post new block into the block relay
  /// @param _blockHash Hash of the block header
  /// @param _drMerkleRoot The root hash of the requests-only merkle tree as contained in the block header.
  /// @param _tallyMerkleRoot The root hash of the tallies-only merkle tree as contained in the block header.
  function postNewBlock(uint256 _blockHash, uint256 _drMerkleRoot, uint256 _tallyMerkleRoot)
    public
    isOwner
    blockDoesNotExist(_blockHash)
  {
    uint256 id = _blockHash;
    blocks[id].drHashMerkleRoot = _drMerkleRoot;
    blocks[id].tallyHashMerkleRoot = _tallyMerkleRoot;
  }

  /// @dev Retrieve the requests-only merkle root hash that was reported for a specific block header.
  /// @param _blockHash Hash of the block header
  /// @return Requests-only merkle root hash in the block header.
  function readDrMerkleRoot(uint256 _blockHash)
    public
    view
    blockExists(_blockHash)
  returns(uint256 drMerkleRoot)
    {
    drMerkleRoot = blocks[_blockHash].drHashMerkleRoot;
  }

  /// @dev Retrieve the tallies-only merkle root hash that was reported for a specific block header.
  /// @param _blockHash Hash of the block header
  /// tallies-only merkle root hash in the block header.
  function readTallyMerkleRoot(uint256 _blockHash)
    public
    view
    blockExists(_blockHash)
  returns(uint256 tallyMerkleRoot)
  {
    tallyMerkleRoot = blocks[_blockHash].tallyHashMerkleRoot;
  }
}
