// SPDX-License-Identifier: WISE

pragma solidity ^0.8.9;

interface Child {

    function initialize(
        uint256 inputParameter
    ) external;
}

contract Factory {

    address public master;
    address public target;

    modifier onlyMaster() {
        require(
            msg.sender == master,
            'Factory: access denied'
        );
        _;
    }

    constructor(
        address _implementation
    ) {
        target = _implementation;
        master = msg.sender;
    }

    function update(
        address _implementation
    )
        external
        onlyMaster
    {
        target = _implementation;
    }

    function delegate(
        address _master
    )
        external
        onlyMaster
    {
        master = _master;
    }

    function revoke()
        external
        onlyMaster
    {
        master = address(0x0);
    }

    function clone(
        uint256 inputParameter
    )
        external
        returns (
            address result
        )
    {
        bytes20 targetBytes = bytes20(target);

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

            result := create(0, clone, 0x37)
        }

        Child _target = Child(result);

        _target.initialize(
            inputParameter
        );
    }
}
