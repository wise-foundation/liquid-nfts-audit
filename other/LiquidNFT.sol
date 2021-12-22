//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract D {
    uint public x;
    constructor(uint a) {
        x = a;
    }
}

contract LiquidNFTFactory is IERC721Receiver {
    using SafeERC20 for IERC20;

    address public masterAddress;
    uint256 public interestRate;

    mapping(bytes32 => address) public assetLoan;

    modifier onlyMaster() {
        msg.sender == masterAddress;
        _;
    }

    event ERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    function createDSalted(bytes32 salt, uint arg) public {
        // This complicated expression just tells you how the address
        // can be pre-computed. It is just there for illustration.
        // You actually only need ``new D{salt: salt}(arg)``.
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(D).creationCode,
                arg
            ))
        )))));

        D d = new D{salt: salt}(arg);
        require(address(d) == predictedAddress);
    }

    function changeInterestRate(uint256 _newInterestRate) external onlyMaster {
        interestRate = _newInterestRate;
    }

    constructor() {
        masterAddress = msg.sender;
    }

    function _createLoan(
        address _assetAddress,
        uint256 _assetId,
        address _nftOwner,
        uint256 _minAmount,
        uint256 _maxAmount,
        address _loanToken,
        uint256 _duration
    ) internal returns (address) {
        LiquidNFT loan = new LiquidNFT(
            address(this),
            _assetAddress,
            _assetId,
            _nftOwner,
            _minAmount,
            _maxAmount,
            _loanToken,
            _duration
        );
        // add nonce to the hash
        assetLoan[getLoanId(_assetAddress, _assetId, _nftOwner)] = address(
            loan
        );
        return address(loan);
    }

    function createLoan(
        address _assetAddress,
        uint256 _assetId,
        address _nftOwner,
        uint256 _floorValue,
        uint256 _deltaValue,
        address _loanToken,
        uint256 _duration
    ) external {
        address newLoan = _createLoan(
            _assetAddress,
            _assetId,
            _nftOwner,
            _floorValue,
            _floorValue + _deltaValue,
            _loanToken,
            _duration
        );

        IERC721(_assetAddress).safeTransferFrom(_nftOwner, address(this), _assetId);
        IERC721(_assetAddress).safeTransferFrom(address(this), newLoan, _assetId);
    }

    function getLoanId(
        address _nft,
        uint256 _id,
        address _owner
    ) public pure returns (bytes32) {
        // add nonce to the hash
        return keccak256(abi.encode(_nft, _id, _owner));
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        override returns (bytes4)
    {
        emit ERC721Received(
            operator,
            from,
            tokenId,
            data
        );
        return this.onERC721Received.selector;
    }
}

contract LiquidNFT is IERC721Receiver {
    using SafeERC20 for IERC20;

    LiquidNFTFactory parent;

    uint256 constant ONE = 10**18;
    uint256 constant splitFee = ONE / 100;
    uint256 constant INTERVAL = 86400;

    address provider; // not set yet
    address defaultReceiver; // not set yet
    address immutable owner;

    IERC20 immutable loanToken;
    IERC721 immutable assetAddress;

    uint256 immutable assetId;
    uint256 immutable minloanAmount;
    uint256 immutable maxloanAmount;
    uint256 immutable creationTime;

    uint256 interestRate; //not set yet
    uint256 loanDeposit;
    uint256 activationTime;

    uint256 loanDuration;
    uint256 lastInterestPayment;
    uint256 totalPayments;
    uint256 public remainingBalance;

    uint256 proposedExtension;
    uint256 extensionActivationTime;
    uint256 extensionProposalTime;
    uint256 extensionDeposits;
    address extensionVoucher;

    // flag/address for single depositor

    mapping(address => uint256) public contributions;
    mapping(address => bool) public withdrawn;

    status public loanStatus;
    enum status {
        CREATED,
        INACTIVE,
        ATTRACTION,
        DEPOSITED,
        DEFAULTED,
        ACTIVE,
        FINISHED
    }

    constructor(
        address _factoryAddress,
        address _assetAddress,
        uint256 _assetId,
        address _NFTOwner,
        uint256 _minAmount,
        uint256 _maxAmount,
        address _loanToken,
        uint256 _duration
    ) {
        owner = _NFTOwner;
        assetId = _assetId;
        minloanAmount = _minAmount;
        maxloanAmount = _maxAmount;
        creationTime = block.timestamp;
        loanDuration = _duration;
        loanStatus = status.CREATED;
        loanToken = IERC20(_loanToken);
        assetAddress = IERC721(_assetAddress);
        parent = LiquidNFTFactory(_factoryAddress);
    }

    uint256 constant EXTENTION_TIME = 3 days;
    uint256 constant THRESHOLD_LIMIT = 51;
    uint256 public voteValue;

    function extendLoan(uint256 extension) external {
        require(loanStatus == status.DEPOSITED, "NFTLoan: not ongonig loan");
        require(msg.sender == owner, "nft owner must extend loan");
        proposedExtension = extension;
        extensionProposalTime = block.timestamp;
    }

    function approveExtension() external {
        require(loanStatus == status.DEPOSITED, "NFTLoan: not ongonig loan");
        require(contributions[msg.sender] > 0, "sender must be a voucher");
        require(
            _daysBefore(activationTime + loanDuration) < 7,
            "loand must be in the last 7 days"
        );
        extensionDeposits += contributions[msg.sender];
        if (extensionDeposits > minloanAmount) {
            extensionActivationTime = block.timestamp;
            remainingBalance =
                remainingBalance *
                (((ONE + interestRate * extensionActivationTime)) / ONE);
        }
    }

    function approveExtension(uint256 _value) external {
        require(loanStatus == status.DEPOSITED, "NFTLoan: not ongonig loan");
        require(
            _daysBefore(activationTime + loanDuration) < 4,
            "loand must be in the last 7 days"
        );
        if (_value > minloanAmount && extensionDeposits < minloanAmount) {
            extensionVoucher = msg.sender;
            extensionDeposits = _value;
        } else {
            extensionDeposits += _value;
            if (extensionDeposits > minloanAmount) {
                extensionActivationTime = block.timestamp;
                remainingBalance =
                    remainingBalance *
                    (((ONE + interestRate * proposedExtension)) / ONE);
            }
        }
        if (extensionDeposits + _value < maxloanAmount) {
            _doDeposit(_value);
            return;
        } else {
            _doDeposit(maxloanAmount - loanDeposit);
            extensionDeposits = maxloanAmount;
            return;
        }
    }

    function depositTokens(
        uint256 _value //tokenAmount
    ) external {
        require(loanStatus == status.CREATED, "loan must be in created status");

        require(
            _daysSince(creationTime) < 10,
            "NFTLoan: already expired" // 32 char max
        );
        if (_value >= maxloanAmount) {
            provider = msg.sender;
            loanToken.safeTransferFrom(
                msg.sender,
                address(this),
                maxloanAmount
            );
            loanDeposit = _value;
            return;
        }

        if (loanDeposit + _value < maxloanAmount) {
            _doDeposit(_value);
            return;
        }

        _doDeposit(maxloanAmount - loanDeposit);

        loanStatus = status.DEPOSITED;
    }

    function activateLoan() external {
        require(
            loanStatus == status.DEPOSITED,
            "loan must be in deposit state"
        );

        loanToken.safeTransfer(owner, loanDeposit);

        loanStatus = status.ACTIVE;

        activationTime = block.timestamp;

        lastInterestPayment = block.timestamp;

        remainingBalance = loanDeposit + _calculateInterest(loanDuration);

        // emit some events
    }

    function deactivateLoan() external {
        if (_daysSince(creationTime) > 10) {
            if (loanDeposit < minloanAmount) {
                loanStatus = status.INACTIVE;
            }
        }
    }

    function refundDeposit() external {
        require(
            loanStatus == status.INACTIVE ||
                extensionVoucher != address(0) ||
                provider != address(0),
            "loan must be inactive"
        );

        uint256 balance = contributions[msg.sender];
        contributions[msg.sender] = 0;

        loanToken.safeTransfer(msg.sender, balance);

        // emit events
    }

    function makePayment(uint256 value) external {
        require(msg.sender == owner, "LiquidNFT makePayment: Not nft owner");
        if (extensionActivationTime > 0) {
            if (_daysSince(extensionActivationTime) > extensionProposalTime) {
                loanStatus = status.DEFAULTED;
                return;
            }
        } else {
            if (_daysSince(activationTime) > loanDuration) {
                loanStatus = status.DEFAULTED;
                return;
            }
        }

        uint256 payValue = remainingBalance >= value ? value : remainingBalance;

        loanToken.safeTransferFrom(owner, address(this), payValue);

        remainingBalance -= payValue;
        totalPayments += payValue;

        _handleLatePayments(_daysSince(lastInterestPayment));

        lastInterestPayment = block.timestamp;

        if (remainingBalance == 0) {
            loanStatus = status.FINISHED;
        }
    }

    function markDefaultLoan() public {
        if (extensionActivationTime > 0) {
            if (_daysSince(extensionActivationTime) > extensionProposalTime) {
                loanStatus = status.DEFAULTED;
                return;
            }
        } else {
            if (_daysSince(activationTime) > loanDuration) {
                loanStatus = status.DEFAULTED;
                return;
            }
        }
    }

    // consider moving to helper file
    function _handleLatePayments(uint256 daysLate) internal {
        if (daysLate > 7) {
            loanStatus = status.DEFAULTED;
            return;
        }

        if (daysLate < 5) {
            remainingBalance =
                remainingBalance +
                daysLate *
                ((loanDeposit * (ONE / 200)) / ONE);
            return;
        }

        remainingBalance =
            remainingBalance +
            4 *
            ((loanDeposit * (ONE / 200)) / ONE) +
            (daysLate - 4) *
            ((loanDeposit * (ONE / 100)) / ONE);
    }

    // consider moving to helper file
    function _calculateInterest(uint256 i) internal view returns (uint256) {
        return (loanDeposit * interestRate * i) / ONE;
    }

    // consider moving to helper file
    function _doDeposit(uint256 _transferValue) internal {
        contributions[msg.sender] = contributions[msg.sender] + _transferValue;

        loanToken.safeTransferFrom(msg.sender, address(this), _transferValue);

        loanDeposit = loanDeposit + _transferValue;
    }

    // consider moving to helper file
    function _daysSince(uint256 _timeStamp) internal view returns (uint256) {
        unchecked {
            return (block.timestamp - _timeStamp) / INTERVAL;
        }
    }

    function _daysBefore(uint256 _timeStamp) internal view returns (uint256) {
        unchecked {
            return (_timeStamp - block.timestamp) / INTERVAL;
        }
    }

    function returnNFT() external {
        require(
            loanStatus == status.FINISHED,
            "loan must be finished for nft return"
        );

        assetAddress.safeTransferFrom(address(this), owner, assetId);
    }

    // for the auction (if separate contract) or single backer
    function withdrawNFT() external {
        require(
            loanStatus == status.DEFAULTED,
            "loan must be finished for nft resturn"
        );

        assetAddress.safeTransferFrom(address(this), address(parent), assetId);
    }

    // fo the backers
    function withdrawEarnedInterest() external {
        require(
            loanStatus == status.FINISHED,
            // loanStatus == status.DEFAULTED,
            // if defaulted NFT goes to the auction
            // the amount gathered in the auction distributed between backers
            "NFTLoan: not finished yet"
        );

        require(
            withdrawn[msg.sender] == false,
            "deposit and interest can only be withdrawn once"
        );

        withdrawn[msg.sender] = true;
        if (provider != address(0)) {
            require(msg.sender == provider, "only the provider can withdraw");
            loanToken.safeTransfer(msg.sender, totalPayments);
        }
        loanToken.safeTransfer(
            msg.sender,
            (totalPayments * contributions[msg.sender]) / loanDeposit
        );
    }

    event Something(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        emit Something(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }
}
