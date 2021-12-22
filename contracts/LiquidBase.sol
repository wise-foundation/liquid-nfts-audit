// SPDX-License-Identifier: WISE

pragma solidity ^0.8.9;

contract LiquidBase {

    //Team fee relative in percentage
    uint256 public constant FEE = 20;
    //Time before a liquidation will occur
    uint256 public constant DEADLINE_TIME = 7 days;
    //How long the contribution phase lasts
    uint256 public constant CONTRIBUTION_TIME = 5 days;
    uint256 public constant SECONDS_IN_DAY = 86400;

    //address if factory that creates lockers
    address public constant FACTORY_ADDRESS =
    0x938bE4C47B909613441427db721B66D73dDd58c0;

    //Address to tranfer NFT to in event of non singleProvider liquidation
    address public constant TRUSTEE_MULTISIG = //0xa803c226c8281550454523191375695928DcFE92
    0x910c094b260c8b1493497a8d6A780f0A48f0b9E7;

    //ERC20 used for payments of this locker
    address public constant PAYMENT_TOKEN =
    0xb70C4d4578AeF63A1CecFF8bF4aE1BCeDD187a6b; //0x264cec4Ff804a9d1884B37371E452152DC1aFeB2; //0xb70C4d4578AeF63A1CecFF8bF4aE1BCeDD187a6b;

    address constant ZERO_ADDRESS = address(0);

    /*@dev
    * @element tokenID: NFT IDs
    * @element tokenAddress: address of NFT contract
    * @element paymentTime: how long loan will last
    * @element paymentRate: how much must be paid for loan
    * @element lockerOwner: who is taking out loan
    */
    struct Globals {
        uint256[] tokenId;
        uint256 paymentTime;
        uint256 paymentRate;
        address lockerOwner;
        address tokenAddress;
    }

    Globals public globals;
    //Address of single provider, is zero address if there is no single provider
    address public singleProvider;

    //Minimum the owner wants for the loan. If less than this contributors refunded
    uint256 public floorAsked;
    //Maximum the owner wants for the loan
    uint256 public totalAsked;
    //How many tokens have been collected for far for this loan
    uint256 public totalCollected;

    //Balance contributors can claim at a given moment
    uint256 public claimableBalance;
    //Balance the locker owner still owes
    uint256 public remainingBalance;
    //Balance of all penalties incurred by locker owner so far
    uint256 public penaltiesBalance;

    //Time next payoff must happen to avoid penalties
    uint256 public nextDueTime;
    //Timestamp initialize was called
    uint256 public creationTime;

    //How much a user has contributed to loan during contribution phase
    mapping(address => uint256) public contributions;
    //How much a user has received payed back for their potion of contributing to the loan
    mapping(address => uint256) public compensations;
}
