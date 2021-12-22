const { BN, erxpectRevert } = require('@openzeppelin/test-helpers');
const LiquidNFT = artifacts.require("LiquidNFT");
const LiquidNFTFactory = artifacts.require("LiquidNFTFactory");
const ERC20 = artifacts.require("Token");
const NFT721 = artifacts.require("NFT721");
const NFT1155 = artifacts.require("NFT1155");
const { expect } = require('chai');
const timeMachine = require('ganache-time-traveler');
const Contract = require('web3-eth-contract');

Contract.setProvider("ws://localhost:9545");

contract("LiquidNFT", async accounts => {

    const [owner, alice, bob] = accounts;

    beforeEach(async() => {

        this.usdc = await ERC20.new("USDC", "USDC");
        this.myNFT = await NFT721.new();
        this.liquidNFTFactory = await LiquidNFTFactory.new();

        await Promise.all([alice, bob].map(
            acc => this.usdc.mint(5000, { from: acc })
        ));

        await this.myNFT.mint();

        const tokenId = await this.myNFT.tokenIds(owner, 0);
        await this.myNFT.approve(this.liquidNFTFactory.address, tokenId);

        const address = await this.liquidNFTFactory.createLoan(
            this.myNFT.address,
            tokenId,
            owner,
            600,
            1000,
            this.usdc.address,
            15 // 2 weeks
        );

        const loanId = await this.liquidNFTFactory.getLoanId(this.myNFT.address, tokenId, owner);

        this.liquidNFTContractAddress = await this.liquidNFTFactory.assetLoan(loanId);
        this.liquidNFT = new Contract(LiquidNFT.abi, this.liquidNFTContractAddress);

        await Promise.all([alice, bob].map(
            acc => this.usdc.approve(this.liquidNFTContractAddress, 5000, { from: acc })
        ));

        expect(new BN(await this.myNFT.balanceOf(this.liquidNFT.options.address)).toNumber())
            .to.equal(new BN(1).toNumber(1));
    });

    describe("LiquidNFT", () => {
        describe("Deactivate Loan and refund", () => {
            it("deposit tokens less than min, deactivate it after 11 days and refund it", async () => {
                await this.liquidNFT.methods.depositTokens(100).send({ from: alice, gas: 200000 });
                await this.liquidNFT.methods.depositTokens(200).send({ from: bob, gas: 200000 });

                const elevenDayTS = 86400 * 11;
                await timeMachine.advanceTimeAndBlock(elevenDayTS);
                await this.liquidNFT.methods.deactivateLoan().send({ from: owner });
                expect(await this.liquidNFT.methods.loanStatus().call()).to.equal("1"); //INACTIVE

                await this.liquidNFT.methods.refundDeposit().send({ from: alice });
                await this.liquidNFT.methods.refundDeposit().send({ from: bob });

                expect(new BN(await this.usdc.balanceOf(alice)).toNumber())
                    .to.equal(new BN(5000).toNumber(5000));
                expect(new BN(await this.usdc.balanceOf(bob)).toNumber())
                    .to.equal(new BN(5000).toNumber(5000));
                expect(new BN(await this.usdc.balanceOf(this.liquidNFTContractAddress)).toNumber())
                    .to.equal(new BN(0).toNumber(0));
            });
        });

        describe("Activate Loan", () => {
            it("deposit token equal to max and activiate it", async () => {
                await this.liquidNFT.methods.depositTokens(800).send({ from: alice, gas: 200000 });
                await this.liquidNFT.methods.depositTokens(800).send({ from: bob, gas: 200000 });

                expect(new BN(await this.usdc.balanceOf(alice)).toNumber())
                    .to.equal(new BN(4200).toNumber(4200));
                expect(new BN(await this.usdc.balanceOf(bob)).toNumber())
                    .to.equal(new BN(4200).toNumber(4200));
                expect(new BN(await this.usdc.balanceOf(this.liquidNFTContractAddress)).toNumber())
                    .to.equal(new BN(1600).toNumber(1600));

                await this.liquidNFT.methods.activateLoan().send({ from: owner, gas: 200000 });

                expect(await this.liquidNFT.methods.loanStatus().call()).to.equal("5"); //ACTIVE
                expect(new BN(await this.usdc.balanceOf(owner)).toNumber())
                    .to.equal(new BN(1600).toNumber(1600));
                expect(new BN(await this.usdc.balanceOf(this.liquidNFTContractAddress)).toNumber())
                    .to.equal(new BN(0).toNumber(0));
            });

        });

        describe("MakePayment, return NFT and withdraw earned Interest", () => {
            it("deposit token, NFT owner pay back, return NFT to owner and vouchers withdraw earned interest ", async () => {
                await this.liquidNFT.methods.depositTokens(800).send({ from: alice, gas: 200000 });
                await this.liquidNFT.methods.depositTokens(800).send({ from: bob, gas: 200000 });

                await this.liquidNFT.methods.activateLoan().send({ from: owner, gas: 200000 });

                await this.usdc.approve(this.liquidNFTContractAddress, 5000);
                await this.liquidNFT.methods.makePayment(600).send({ from: owner, gas: 200000 });

                let laterDays = 86400 * 4; // 4 days later
                await timeMachine.advanceTimeAndBlock(laterDays);
                await this.liquidNFT.methods.makePayment(200).send({ from: owner, gas: 200000 });
                // (1600 - 600 - 200) + 4 * 1600 / 200 = 832
                expect(new BN(await this.liquidNFT.methods.remainingBalance().call()).toNumber())
                    .to.equal(new BN(832).toNumber(832));

                laterDays = 86400 * 6; // 6 days later
                await timeMachine.advanceTimeAndBlock(laterDays);
                await this.liquidNFT.methods.makePayment(200).send({ from: owner, gas: 200000 });
                // 832 - 200 + 4 * 1600 / 200 + (6 - 4) * 1600 / 100 = 696
                expect(new BN(await this.liquidNFT.methods.remainingBalance().call()).toNumber())
                    .to.equal(new BN(696).toNumber(696));

                // Owner gets some profit
                await this.usdc.mint(100, { from: owner });

                await this.liquidNFT.methods.makePayment(700).send({ from: owner, gas: 200000 });
                expect(await this.liquidNFT.methods.loanStatus().call()).to.equal("6"); //FINISHED
                expect(new BN(await this.usdc.balanceOf(this.liquidNFTContractAddress)).toNumber())
                    .to.equal(new BN(1696).toNumber(1696)); // 1600 - 696
                expect(new BN(await this.usdc.balanceOf(owner)).toNumber())
                    .to.equal(new BN(4).toNumber(4)); // 700 - 696

                // Return NFT
                const tokenId = await this.myNFT.tokenIds(owner, 0);
                await this.liquidNFT.methods.returnNFT().send({ from: owner });
                expect(new BN(await this.myNFT.balanceOf(owner)).toNumber())
                    .to.equal(new BN(1).toNumber(1));

                // Withdraw earned interest
                await this.liquidNFT.methods.withdrawEarnedInterest().send({ from: alice });
                await this.liquidNFT.methods.withdrawEarnedInterest().send({ from: bob });
                expect(new BN(await this.usdc.balanceOf(alice)).toNumber())
                    .to.equal(new BN(5048).toNumber(5048)); // 5000 - 800 + 1696 * 800 / 1600
                expect(new BN(await this.usdc.balanceOf(bob)).toNumber())
                    .to.equal(new BN(5048).toNumber(5048));
            });
        });

        describe("Withdraw NFT", () => {
            it("Do not pay interest more than 15 days and NFT is withdrawn", async () => {
                await this.liquidNFT.methods.depositTokens(800).send({ from: alice, gas: 200000 });
                await this.liquidNFT.methods.depositTokens(800).send({ from: bob, gas: 200000 });

                await this.liquidNFT.methods.activateLoan().send({ from: owner, gas: 200000 });

                await this.usdc.approve(this.liquidNFTContractAddress, 5000);

                let laterDays = 86400 * 16; // 16 days later
                await timeMachine.advanceTimeAndBlock(laterDays);
                await this.liquidNFT.methods.makePayment(200).send({ from: owner, gas: 200000 });

                expect(await this.liquidNFT.methods.loanStatus().call()).to.equal("4"); //DEFAULTED
                await this.liquidNFT.methods.withdrawNFT().send({ from: owner });
                expect(new BN(await this.myNFT.balanceOf(this.liquidNFTFactory.address)).toNumber())
                    .to.equal(new BN(1).toNumber(1));
            });
        });
    });
})
