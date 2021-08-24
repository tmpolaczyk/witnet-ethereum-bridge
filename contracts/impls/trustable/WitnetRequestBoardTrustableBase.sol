// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../WitnetRequestBoardUpgradableBase.sol";
import "../../data/WitnetBoardDataACLs.sol";
import "../../interfaces/IWitnetRequestBoardAdmin.sol";
import "../../interfaces/IWitnetRequestBoardAdminACLs.sol";
import "../../libs/WitnetParserLib.sol";
import "../../patterns/Payable.sol";

/// @title Witnet Request Board "trustable" base implementation contract.
/// @notice Contract to bridge requests to Witnet Decentralized Oracle Network.
/// @dev This contract enables posting requests that Witnet bridges will insert into the Witnet network.
/// The result of the requests will be posted back to this contract by the bridge nodes too.
/// @author The Witnet Foundation
abstract contract WitnetRequestBoardTrustableBase
    is
        Payable,
        IWitnetRequestBoardAdmin,
        IWitnetRequestBoardAdminACLs,
        WitnetBoardDataACLs,
        WitnetRequestBoardUpgradableBase
{
    using Witnet for bytes;
    using WitnetParserLib for Witnet.Result;

    uint256 internal constant _ESTIMATED_REPORT_RESULT_GAS = 102496;

    constructor(bool _upgradable, bytes32 _versionTag, address _currency)
        Payable(_currency)
        WitnetRequestBoardUpgradableBase(_upgradable, _versionTag)
    {}


    // ================================================================================================================
    // --- Overrides 'Upgradable' -------------------------------------------------------------------------------------

    /// Initialize storage-context when invoked as delegatecall.
    /// @dev Must fail when trying to initialize same instance more than once.
    function initialize(bytes memory _initData) virtual external override {
        address _owner = _state().owner;
        if (_owner == address(0)) {
            // set owner if none set yet
            _owner = msg.sender;
            _state().owner = _owner;
        } else {
            // only owner can initialize:
            require(msg.sender == _owner, "WitnetRequestBoardTrustableBase: only owner");
        }

        if (_state().base != address(0)) {
            // current implementation cannot be initialized more than once:
            require(_state().base != base(), "WitnetRequestBoardTrustableBase: already initialized");
        }
        _state().base = base();

        emit Upgraded(msg.sender, base(), codehash(), version());

        // Do actual base initialization:
        setReporters(abi.decode(_initData, (address[])));
    }

    /// Tells whether provided address could eventually upgrade the contract.
    function isUpgradableFrom(address _from) external view override returns (bool) {
        address _owner = _state().owner;
        return (
            // false if the WRB is intrinsically not upgradable, or `_from` is no owner
            isUpgradable()
                && _owner == _from
        );
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestBoardAdmin' ----------------------------------------------------------

    /// Gets admin/owner address.
    function owner()
        public view
        override
        returns (address)
    {
        return _state().owner;
    }

    /// Transfers ownership.
    function transferOwnership(address _newOwner)
        external
        virtual override
        onlyOwner
    {
        address _owner = _state().owner;
        if (_newOwner != _owner) {
            _state().owner = _newOwner;
            emit OwnershipTransferred(_owner, _newOwner);
        }
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestBoardAdminACLs' ------------------------------------------------------

    /// Tells whether given address is included in the active reporters control list.
    /// @param _reporter The address to be checked.
    function isReporter(address _reporter) public view override returns (bool) {
        return _acls().isReporter_[_reporter];
    }

    /// Adds given addresses to the active reporters control list.
    /// @dev Can only be called from the owner address.
    /// @dev Emits the `ReportersSet` event.
    /// @param _reporters List of addresses to be added to the active reporters control list.
    function setReporters(address[] memory _reporters)
        public
        override
        onlyOwner
    {
        for (uint ix = 0; ix < _reporters.length; ix ++) {
            address _reporter = _reporters[ix];
            _acls().isReporter_[_reporter] = true;
        }
        emit ReportersSet(_reporters);
    }

    /// Removes given addresses from the active reporters control list.
    /// @dev Can only be called from the owner address.
    /// @dev Emits the `ReportersUnset` event.
    /// @param _exReporters List of addresses to be added to the active reporters control list.
    function unsetReporters(address[] memory _exReporters)
        public
        override
        onlyOwner
    {
        for (uint ix = 0; ix < _exReporters.length; ix ++) {
            address _reporter = _exReporters[ix];
            _acls().isReporter_[_reporter] = false;
        }
        emit ReportersUnset(_exReporters);
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestBoardReporter' -------------------------------------------------------

    /// Reports the Witnet-provided result to a previously posted request.
    /// @dev Will assume `block.timestamp` as the timestamp at which the request was solved.
    /// @dev Fails if:
    /// @dev - the `_queryId` is not in 'Posted' status.
    /// @dev - provided `_drTxHash` is zero;
    /// @dev - length of provided `_result` is zero.
    /// @param _queryId The unique identifier of the data request.
    /// @param _drTxHash The hash of the solving tally transaction in Witnet.
    /// @param _cborBytes The result itself as bytes.
    function reportResult(
            uint256 _queryId,
            bytes32 _drTxHash,
            bytes calldata _cborBytes
        )
        external
        override
        onlyReporters
        inStatus(_queryId, Witnet.QueryStatus.Posted)
    {
        // solhint-disable not-rely-on-time
        _reportResult(_queryId, block.timestamp, _drTxHash, _cborBytes);
    }

    /// Reports the Witnet-provided result to a previously posted request.
    /// @dev Fails if:
    /// @dev - called from unauthorized address;
    /// @dev - the `_queryId` is not in 'Posted' status.
    /// @dev - provided `_drTxHash` is zero;
    /// @dev - length of provided `_result` is zero.
    /// @param _queryId The unique query identifier
    /// @param _timestamp The timestamp of the solving tally transaction in Witnet.
    /// @param _drTxHash The hash of the solving tally transaction in Witnet.
    /// @param _cborBytes The result itself as bytes.
    function reportResult(
            uint256 _queryId,
            uint256 _timestamp,
            bytes32 _drTxHash,
            bytes calldata _cborBytes
        )
        external
        override
        onlyReporters
        inStatus(_queryId, Witnet.QueryStatus.Posted)
    {
        _reportResult(_queryId, _timestamp, _drTxHash, _cborBytes);
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestBoardRequestor' ------------------------------------------------------

    /// Retrieves copy of all response data related to a previously posted request, removing the whole query from storage.
    /// @dev Fails if the `_queryId` is not in 'Reported' status, or called from an address different to
    /// @dev the one that actually posted the given request.
    /// @param _queryId The unique query identifier.
    function deleteQuery(uint256 _queryId)
        public
        virtual override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (Witnet.Response memory _response)
    {
        Witnet.Query storage _query = _state().queries[_queryId];
        require(
            msg.sender == _query.request.requester,
            "WitnetRequestBoardTrustableBase: only requester"
        );
        _response = _query.response;
        delete _state().queries[_queryId];
        emit DeletedQuery(_queryId, msg.sender);
    }

    /// Requests the execution of the given Witnet Data Request in expectation that it will be relayed and solved by the Witnet DON.
    /// A reward amount is escrowed by the Witnet Request Board that will be transferred to the reporter who relays back the Witnet-provided
    /// result to this request.
    /// @dev Fails if:
    /// @dev - provided reward is too low.
    /// @dev - provided script is zero address.
    /// @dev - provided script bytecode is empty.
    /// @param _addr The address of a IWitnetRequest contract, containing the actual Data Request seralized bytecode.
    /// @return _queryId An unique query identifier.
    function postRequest(IWitnetRequest _addr)
        public payable
        virtual override
        returns (uint256 _queryId)
    {
        uint256 _value = _getMsgValue();
        uint256 _gasPrice = _getGasPrice();

        // Checks the tally reward is covering gas cost
        uint256 minResultReward = _gasPrice * _ESTIMATED_REPORT_RESULT_GAS;
        require(_value >= minResultReward, "WitnetRequestBoardTrustableBase: reward too low");

        // Validates provided script:
        require(address(_addr) != address(0), "WitnetRequestBoardTrustableBase: null script");
        bytes memory _bytecode = _addr.bytecode();
        require(_bytecode.length > 0, "WitnetRequestBoardTrustableBase: empty script");

        _queryId = ++ _state().numQueries;

        Witnet.Request storage _request = _getRequestData(_queryId);
        _request.requester = msg.sender;
        _request.addr = _addr;
        _request.hash = _bytecode.hash();
        _request.gasprice = _gasPrice;
        _request.reward = _value;

        // Let observers know that a new request has been posted
        emit PostedRequest(_queryId, msg.sender);
    }

    /// Increments the reward of a previously posted request by adding the transaction value to it.
    /// @dev Updates request `gasPrice` in case this method is called with a higher
    /// @dev gas price value than the one used in previous calls to `postRequest` or
    /// @dev `upgradeReward`.
    /// @dev Fails if the `_queryId` is not in 'Posted' status.
    /// @dev Fails also in case the request `gasPrice` is increased, and the new
    /// @dev reward value gets below new recalculated threshold.
    /// @param _queryId The unique query identifier.
    function upgradeReward(uint256 _queryId)
        public payable
        virtual override
        inStatus(_queryId, Witnet.QueryStatus.Posted)
    {
        Witnet.Request storage _request = _getRequestData(_queryId);

        uint256 _newReward = _request.reward + _getMsgValue();
        uint256 _newGasPrice = _getGasPrice();

        // If gas price is increased, then check if new rewards cover gas costs
        if (_newGasPrice > _request.gasprice) {
            // Checks the reward is covering gas cost
            uint256 _minResultReward = _newGasPrice * _ESTIMATED_REPORT_RESULT_GAS;
            require(
                _newReward >= _minResultReward,
                "WitnetRequestBoardTrustableBase: reward too low"
            );
            _request.gasprice = _newGasPrice;
        }
        _request.reward = _newReward;
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestBoardView' -----------------------------------------------------------

    /// Estimates the amount of reward we need to insert for a given gas price.
    /// @param _gasPrice The gas price for which we need to calculate the rewards.
    function estimateReward(uint256 _gasPrice)
        external view
        virtual override
        returns (uint256)
    {
        return _gasPrice * _ESTIMATED_REPORT_RESULT_GAS;
    }

    /// Returns next request id to be generated by the Witnet Request Board.
    function getNextQueryId()
        external view
        override
        returns (uint256)
    {
        return _state().numQueries + 1;
    }

    /// Gets the whole Query data contents, if any, no matter its current status.
    function getQueryData(uint256 _queryId)
      external view
      override
      returns (Witnet.Query memory)
    {
        return _state().queries[_queryId];
    }

    /// Gets current status of given query.
    function getQueryStatus(uint256 _queryId)
        external view
        override
        returns (Witnet.QueryStatus)
    {
        return _getQueryStatus(_queryId);

    }

    /// Retrieves the whole Request record posted to the Witnet Request Board.
    /// @dev Fails if the `_queryId` is not valid or, if it has been deleted,
    /// @dev or if the related script bytecode got changed after being posted.
    /// @param _queryId The unique identifier of a previously posted query.
    function readRequest(uint256 _queryId)
        external view
        override
        notDeleted(_queryId)
        returns (Witnet.Request memory)
    {
        return _checkRequest(_queryId);
    }

    /// Retrieves the Witnet data request actual bytecode of a previously posted request.
    /// @dev Fails if the `_queryId` is not valid or, if it has been deleted,
    /// @dev or if the related script bytecode got changed after being posted.
    /// @param _queryId The unique identifier of the request query.
    function readRequestBytecode(uint256 _queryId)
        external view
        override
        notDeleted(_queryId)
        returns (bytes memory _bytecode)
    {
        Witnet.Request storage _request = _getRequestData(_queryId);
        if (address(_request.addr) != address(0)) {
            // if DR's request contract address is not zero,
            // we assume the DR has not been deleted, so
            // DR's bytecode can still be fetched:
            _bytecode = _request.addr.bytecode();
            require(
                _bytecode.hash() == _request.hash,
                "WitnetRequestBoardTrustableBase: bytecode changed after posting"
            );
        }
    }

    /// Retrieves the gas price that any assigned reporter will have to pay when reporting
    /// result to a previously posted Witnet data request.
    /// @dev Fails if the `_queryId` is not valid or, if it has been deleted,
    /// @dev or if the related script bytecode got changed after being posted.
    /// @param _queryId The unique query identifier
    function readRequestGasPrice(uint256 _queryId)
        external view
        override
        notDeleted(_queryId)
        returns (uint256)
    {
        return _checkRequest(_queryId).gasprice;
    }

    /// Retrieves the reward currently set for a previously posted request.
    /// @dev Fails if the `_queryId` is not valid or, if it has been deleted,
    /// @dev or if the related script bytecode got changed after being posted.
    /// @param _queryId The unique query identifier
    function readRequestReward(uint256 _queryId)
        external view
        override
        notDeleted(_queryId)
        returns (uint256)
    {
        return _checkRequest(_queryId).reward;
    }

    /// Retrieves the Witnet-provided result, and metadata, to a previously posted request.
    /// @dev Fails if the `_queryId` is not in 'Reported' status.
    /// @param _queryId The unique query identifier
    function readResponse(uint256 _queryId)
        external view
        override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (Witnet.Response memory _response)
    {
        return _getResponseData(_queryId);
    }

    /// Retrieves the hash of the Witnet transaction hash that actually solved the referred query.
    /// @dev Fails if the `_queryId` is not in 'Reported' status.
    /// @param _queryId The unique query identifier.
    function readResponseDrTxHash(uint256 _queryId)
        external view
        override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (bytes32)
    {
        return _getResponseData(_queryId).drTxHash;
    }

    /// Retrieves the address that reported the result to a previously-posted request.
    /// @dev Fails if the `_queryId` is not in 'Reported' status.
    /// @param _queryId The unique query identifier
    function readResponseReporter(uint256 _queryId)
        external view
        override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (address)
    {
        return _getResponseData(_queryId).reporter;
    }

    /// Retrieves the Witnet-provided CBOR-bytes result of a previously posted request.
    /// @dev Fails if the `_queryId` is not in 'Reported' status.
    /// @param _queryId The unique query identifier
    function readResponseResult(uint256 _queryId)
        external view
        override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (Witnet.Result memory)
    {
        Witnet.Response storage _response = _getResponseData(_queryId);
        return WitnetParserLib.resultFromCborBytes(_response.cborBytes);
    }

    /// Retrieves the timestamp in which the result to the referred query was solved by the Witnet DON.
    /// @dev Fails if the `_queryId` is not in 'Reported' status.
    /// @param _queryId The unique query identifier.
    function readResponseTimestamp(uint256 _queryId)
        external view
        override
        inStatus(_queryId, Witnet.QueryStatus.Reported)
        returns (uint256)
    {
        return _getResponseData(_queryId).timestamp;
    }


    // ================================================================================================================
    // --- Full implementation of 'IWitnetRequestParser' interface ----------------------------------------------------

    /// Decode raw CBOR bytes into a Witnet.Result instance.
    /// @param _cborBytes Raw bytes representing a CBOR-encoded value.
    /// @return A `Witnet.Result` instance.
    function resultFromCborBytes(bytes memory _cborBytes)
        external pure
        override
        returns (Witnet.Result memory)
    {
        return WitnetParserLib.resultFromCborBytes(_cborBytes);
    }

    /// Decode a CBOR value into a Witnet.Result instance.
    /// @param _cborValue An instance of `Witnet.CBOR`.
    /// @return A `Witnet.Result` instance.
    function resultFromCborValue(Witnet.CBOR memory _cborValue)
        external pure
        override
        returns (Witnet.Result memory)
    {
        return WitnetParserLib.resultFromCborValue(_cborValue);
    }

    /// Tell if a Witnet.Result is successful.
    /// @param _result An instance of Witnet.Result.
    /// @return `true` if successful, `false` if errored.
    function isOk(Witnet.Result memory _result)
        external pure
        override
        returns (bool)
    {
        return _result.isOk();
    }

    /// Tell if a Witnet.Result is errored.
    /// @param _result An instance of Witnet.Result.
    /// @return `true` if errored, `false` if successful.
    function isError(Witnet.Result memory _result)
        external pure
        override
        returns (bool)
    {
        return _result.isError();
    }

    /// Decode a bytes value from a Witnet.Result as a `bytes` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `bytes` decoded from the Witnet.Result.
    function asBytes(Witnet.Result memory _result)
        external pure
        override returns (bytes memory)
    {
        return _result.asBytes();
    }

    /// Decode an error code from a Witnet.Result as a member of `Witnet.ErrorCodes`.
    /// @param _result An instance of `Witnet.Result`.
    /// @return The `CBORValue.Error memory` decoded from the Witnet.Result.
    function asErrorCode(Witnet.Result memory _result)
        external pure
        override
        returns (Witnet.ErrorCodes)
    {
        return _result.asErrorCode();
    }

    /// Generate a suitable error message for a member of `Witnet.ErrorCodes` and its corresponding arguments.
    /// @dev WARN: Note that client contracts should wrap this function into a try-catch foreseing potential errors generated in this function
    /// @param _result An instance of `Witnet.Result`.
    /// @return A tuple containing the `CBORValue.Error memory` decoded from the `Witnet.Result`, plus a loggable error message.
    function asErrorMessage(Witnet.Result memory _result)
        external pure
        override
        returns (Witnet.ErrorCodes, string memory)
    {
        return _result.asErrorMessage();
    }

    /// Decode a raw error from a `Witnet.Result` as a `uint64[]`.
    /// @param _result An instance of `Witnet.Result`.
    /// @return The `uint64[]` raw error as decoded from the `Witnet.Result`.
    function asRawError(Witnet.Result memory _result)
        external pure
        override
        returns(uint64[] memory)
    {
        return _result.asRawError();
    }

    /// Decode a boolean value from a Witnet.Result as an `bool` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `bool` decoded from the Witnet.Result.
    function asBool(Witnet.Result memory _result)
        external pure
        override
        returns (bool)
    {
        return _result.asBool();
    }

    /// Decode a fixed16 (half-precision) numeric value from a Witnet.Result as an `int32` value.
    /// @dev Due to the lack of support for floating or fixed point arithmetic in the EVM, this method offsets all values.
    /// by 5 decimal orders so as to get a fixed precision of 5 decimal positions, which should be OK for most `fixed16`.
    /// use cases. In other words, the output of this method is 10,000 times the actual value, encoded into an `int32`.
    /// @param _result An instance of Witnet.Result.
    /// @return The `int128` decoded from the Witnet.Result.
    function asFixed16(Witnet.Result memory _result)
        external pure
        override
        returns (int32)
    {
        return _result.asFixed16();
    }

    /// Decode an array of fixed16 values from a Witnet.Result as an `int128[]` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `int128[]` decoded from the Witnet.Result.
    function asFixed16Array(Witnet.Result memory _result)
        external pure
        override
        returns (int32[] memory)
    {
        return _result.asFixed16Array();
    }

    /// Decode a integer numeric value from a Witnet.Result as an `int128` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `int128` decoded from the Witnet.Result.
    function asInt128(Witnet.Result memory _result)
        external pure
        override
        returns (int128)
    {
        return _result.asInt128();
    }

    /// Decode an array of integer numeric values from a Witnet.Result as an `int128[]` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `int128[]` decoded from the Witnet.Result.
    function asInt128Array(Witnet.Result memory _result)
        external pure
        override
        returns (int128[] memory)
    {
        return _result.asInt128Array();
    }

    /// Decode a string value from a Witnet.Result as a `string` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `string` decoded from the Witnet.Result.
    function asString(Witnet.Result memory _result)
        external pure
        override
        returns (string memory)
    {
        return _result.asString();
    }

    /// Decode an array of string values from a Witnet.Result as a `string[]` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `string[]` decoded from the Witnet.Result.
    function asStringArray(Witnet.Result memory _result)
        external pure
        override
        returns (string[] memory)
    {
        return _result.asStringArray();
    }

    /// Decode a natural numeric value from a Witnet.Result as a `uint64` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `uint64` decoded from the Witnet.Result.
    function asUint64(Witnet.Result memory _result)
        external pure
        override
        returns(uint64)
    {
        return _result.asUint64();
    }

    /// Decode an array of natural numeric values from a Witnet.Result as a `uint64[]` value.
    /// @param _result An instance of Witnet.Result.
    /// @return The `uint64[]` decoded from the Witnet.Result.
    function asUint64Array(Witnet.Result memory _result)
        external pure
        override
        returns (uint64[] memory)
    {
        return _result.asUint64Array();
    }


    // ================================================================================================================
    // --- Internal functions -----------------------------------------------------------------------------------------

    function _checkRequest(uint256 _queryId)
        internal view
        returns (Witnet.Request storage _request)
    {
        _request = _getRequestData(_queryId);
        if (address(_request.addr) != address(0)) {
            // if the script contract address is not zero,
            // we assume the query has not been deleted, so
            // the request script bytecode can still be fetched:
            bytes memory _bytecode = _request.addr.bytecode();
            require(
                _bytecode.hash() == _request.hash,
                "WitnetRequestBoardTrustableBase: bytecode changed after posting"
            );
        }
    }

    function _reportResult(
            uint256 _queryId,
            uint256 _timestamp,
            bytes32 _drTxHash,
            bytes memory _cborBytes
        )
        internal
    {
        require(_drTxHash != 0, "WitnetRequestBoardTrustableDefault: Witnet drTxHash cannot be zero");
        // Ensures the result byes do not have zero length
        // This would not be a valid encoding with CBOR and could trigger a reentrancy attack
        require(_cborBytes.length != 0, "WitnetRequestBoardTrustableDefault: result cannot be empty");

        Witnet.Query storage _query = _state().queries[_queryId];
        Witnet.Response storage _response = _query.response;

        // solhint-disable not-rely-on-time
        _response.timestamp = _timestamp;
        _response.drTxHash = _drTxHash;
        _response.reporter = msg.sender;
        _response.cborBytes = _cborBytes;

        _safeTransferTo(payable(msg.sender), _query.request.reward);
        emit PostedResult(_queryId, msg.sender);
    }
}
