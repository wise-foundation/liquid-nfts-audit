// SPDX-License-Identifier: WISE

pragma solidity ^0.8.9;

import "./LiquidTransfer.sol";

interface ILiquidLockerV2 {

    function initialize(
        uint256[] calldata _tokenId,
        address _tokenAddress,
        address _tokenOwner,
        uint256 _floorAsked,
        uint256 _totalAsked,
        uint256 _paymentTime,
        uint256 _paymentRate
    )
        external;

    function PAYMENT_TOKEN()
        external
        view
        returns (address);
}

contract LiquidFactoryV2 is LiquidTransfer {

    uint256 public lockerCount;
    address public masterAddress;
    address public defaultTarget;

    mapping(address => address) public implementations;

    event NewLocker(
        address lockerAddress
    );

    event NewEmtyLocker(
        address lockerAddress
    );

    event ReusedLocker(
        address lockerAddress
    );

    modifier onlyMaster() {
        require(
            msg.sender == masterAddress,
            'LiquidFactory: INVALID_MASTER'
        );
        _;
    }

    constructor(
        address _defaultToken,
        address _defaultTarget
    ) {
        defaultTarget = _defaultTarget;
        implementations[_defaultToken] = _defaultTarget;
        masterAddress = msg.sender;
    }

    function updateDefaultTarget(
        address _newDefaultTarget
    )
        external
        onlyMaster
    {
        defaultTarget = _newDefaultTarget;
    }

    function updateImplementation(
        address _tokenAddress,
        address _targetAddress
    )
        external
        onlyMaster
    {
        implementations[_tokenAddress] = _targetAddress;
    }

    function updateMaster(
        address _newMaster
    )
        external
        onlyMaster
    {
        masterAddress = _newMaster;
    }

    function revokeMaster()
        external
        onlyMaster
    {
        masterAddress = address(0x0);
    }

    function createEmptyLocker(
        address _paymentToken
    )
        external
        returns (address lockerAddress)
    {
        bytes32 salt = keccak256(
            abi.encodePacked(
                lockerCount++
            )
        );

        bytes20 targetBytes = bytes20(
            getImplementation(_paymentToken)
        );

        assembly {

            let clone := mload(0x40)

            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )

            mstore(
                add(clone, 0x14),
                targetBytes
            )

            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            lockerAddress := create2(0, clone, 0x37, salt)
        }

        emit NewEmtyLocker(
            lockerAddress
        );
    }

    function createLiquidLocker(
        uint256[] calldata _tokenId,
        address _tokenAddress,
        uint256 _floorAsked,
        uint256 _totalAsked,
        uint256 _paymentTime,
        uint256 _paymentRate,
        address _paymentToken
    )
        external
        returns (address lockerAddress)
    {
        bytes32 salt = keccak256(
            abi.encodePacked(
                lockerCount++
            )
        );

        bytes20 targetBytes = bytes20(
            getImplementation(_paymentToken)
        );

        assembly {

            let clone := mload(0x40)

            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )

            mstore(
                add(clone, 0x14),
                targetBytes
            )

            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            lockerAddress := create2(0, clone, 0x37, salt)
        }

        ILiquidLockerV2(lockerAddress).initialize(
            _tokenId,
            _tokenAddress,
            msg.sender,
            _floorAsked,
            _totalAsked,
            _paymentRate,
            _paymentTime
        );

        for (uint256 i = 0; i < _tokenId.length; i++) {
            _transferFromNFT(
                msg.sender,
                lockerAddress,
                _tokenAddress,
                _tokenId[i]
            );
        }

        emit NewLocker(
            lockerAddress
        );
    }

   function reuseLiquidLocker(
        uint256[] calldata _tokenId,
        address _tokenAddress,
        uint256 _floorAsked,
        uint256 _totalAsked,
        uint256 _paymentTime,
        uint256 _paymentRate,
        uint256 _lockerIndex,
        address _paymentToken
    )
        external
    {
        address lockerAddress = predictLockerAddrss(
            _lockerIndex,
            address(this),
            getImplementation(_paymentToken)
        );

        require(
            ILiquidLockerV2(lockerAddress).PAYMENT_TOKEN() == _paymentToken,
            'LiquidFactory: INVALID_PAYMENT_TOKEN'
        );

        ILiquidLockerV2(lockerAddress).initialize(
            _tokenId,
            _tokenAddress,
            msg.sender,
            _floorAsked,
            _totalAsked,
            _paymentTime,
            _paymentRate
        );

        for (uint256 i = 0; i < _tokenId.length; i++) {
            _transferFromNFT(
                msg.sender,
                lockerAddress,
                _tokenAddress,
                _tokenId[i]
            );
        }

        emit ReusedLocker(
            lockerAddress
        );
    }

    function getImplementation(
        address _paymentToken
    )
        public
        view
        returns (address implementation)
    {
        implementation =
        implementations[_paymentToken] == address(0x0)
                ? defaultTarget
                : implementations[_paymentToken];
    }

    function predictLockerAddrss(
        uint256 _count,
        address _factory,
        address _implementation
    )
        public
        pure
        returns (address predicted)
    {
        bytes32 salt = keccak256(
            abi.encodePacked(
                _count
            )
        );

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, _implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, _factory))
            mstore(add(ptr, 0x4c), salt)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }
}
