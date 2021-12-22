// SPDX-License-Identifier: AA

pragma solidity ^0.8.0;

import "./Bytecode.sol";

library SSTORE2 {
    error WriteError();

    function write(
        bytes memory _data
    )
        internal
        returns (address pointer)
    {
        bytes memory code = Bytecode.creationCodeFor(
            abi.encodePacked(
                hex'00',
                _data
            )
        );

        assembly {
            pointer := create(0, add(code, 32), mload(code))
        }

        if (pointer == address(0x0)) {
            revert WriteError();
        }
    }

    function read(
        address _pointer
    )
        internal
        view
        returns (bytes memory)
    {
        return Bytecode.codeAt(
            _pointer,
            1,
            type(uint256).max
        );
    }

    function read(
        address _pointer,
        uint256 _start
    )
        internal
        view
        returns (bytes memory)
    {
        return Bytecode.codeAt(
            _pointer,
            _start + 1,
            type(uint256).max
        );
    }

    function read(
        address _pointer,
        uint256 _start,
        uint256 _end
    )
        internal
        view
        returns (bytes memory)
    {
        return Bytecode.codeAt(
            _pointer,
            _start + 1,
            _end + 1
        );
    }
}
