const LiquidLocker = artifacts.require("LiquidLocker");
const LiquidFactory = artifacts.require("LiquidFactoryV2");

const { BN, erxpectRevert } = require('@openzeppelin/test-helpers');

const ERC20 = artifacts.require("Token");
const NFT721 = artifacts.require("NFT721");
const NFT1155 = artifacts.require("NFT1155");

const { expect } = require('chai');
const timeMachine = require('ganache-time-traveler');
const Contract = require('web3-eth-contract');

Contract.setProvider("ws://localhost:9545");

const getLastEvent = async (eventName, instance) => {
    const events = await instance.getPastEvents(eventName, {
        fromBlock: 0,
        toBlock: "latest",
    });
    return events.pop().returnValues;
};

contract("LiquidFactory", async accounts => {

    const [owner, alice, bob] = accounts;

    let nft
    let usdc
    let factory
    let locker

    beforeEach(async() => {

        usdc = await ERC20.new(
            "USDC",
            "USDC"
        );

        locker = await LiquidLocker.new()

        nft = await NFT721.new();
        factory = await LiquidFactory.new(
            usdc.address,
            locker.address
        );

        await Promise.all([alice, bob].map(
            acc => usdc.mint(
                5000,
                {from: acc }
            )
        ));

        await nft.mint();

        const tokenId = await nft.tokenIds(
            owner,
            0
        );

        console.log(tokenId.toNumber(), 'tokenId');

        await nft.approve(
            factory.address,
            tokenId,
            {from: owner}
        );

        //let lockerAddress =
        await factory.createLiquidLocker(
            [tokenId],
            nft.address,
            600,
            600,
            5,
            10,
            usdc.address,
            {from: owner, gas: 3000000}
        );


        const { lockerAddress } = await getLastEvent(
            "NewLocker",
            factory
        );


        //lockerAddress = lockerAddress.toString();

        await Promise.all([alice, bob].map(
            acc => usdc.approve(
                lockerAddress,
                5000,
                { from: acc }
            )
        ));

        const nftBalance = await nft.balanceOf(
            lockerAddress
        );

        console.log(lockerAddress.toString());

        locker = await LiquidLocker.at(lockerAddress);

        assert.equal(
            new BN(nftBalance).toNumber(),
            new BN(1).toNumber()
        );
    });

    describe("LiquidFactory", () => {

        describe("Deactivate and Reuse", () => {

            it("Deactivate and Reuse", async () => {

                await locker.disableLocker();

                const tokenId = await nft.tokenIds(
                    owner,
                    0
                );

                const who = await nft.ownerOf(tokenId);

                const globals = await locker.globals('3');

                console.log(globals['lockerOwner'].toString(), "locker globals owner");
                console.log(owner.toString(), "owner");
                console.log(who.toString(), 'who owns nft');

                await nft.approve(
                    factory.address,
                    tokenId,
                    {from: owner}
                );

                await factory.reuseLiquidLocker(
                    [tokenId],
                    nft.address,
                    600,
                    600,
                    5,
                    10,
                    usdc.address,
                    locker.address,
                    {from: owner, gas: 3000000}
                );

                await locker.makeContribution(
                    100,
                    {
                        from: alice,
                        gas: 200000
                    }
                );

                await locker.makeContribution(
                    200,
                    {
                        from: bob,
                        gas: 200000
                    }
                );
            });
            it.skip("Allow create Empty Locker", async () => {
                await factory.createEmptyLocker();
            });

            it.skip("Allow create Empty Locker and REUSE", async () => {

                await locker.disableLocker();
                await factory.createEmptyLocker();

                const { lockerAddress } = await getLastEvent(
                    "EmptyLocker",
                    factory
                );

                locker = await LiquidLocker.at(lockerAddress);

                const tokenId = await nft.tokenIds(
                    owner,
                    0
                );

                await nft.approve(
                    factory.address,
                    tokenId,
                    {from: owner}
                );

                await factory.reuseLiquidLocker(
                    [tokenId],
                    nft.address,
                    600,
                    600,
                    5,
                    10,
                    usdc.address,
                    locker.address,
                    {from: owner, gas: 3000000}
                );
            });
        });
    });
})
