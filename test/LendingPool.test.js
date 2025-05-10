const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LendingPool", function () {
  let LendingPool;
  let lendingPool;
  let owner;
  let lender;
  let borrower;
  let polkaVMBridge;
  let token;

  beforeEach(async function () {
    // Deploy mock ERC20 token
    const Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Mock Token", "MTK");
    await token.deployed();

    // Deploy LendingPool
    LendingPool = await ethers.getContractFactory("LendingPool");
    [owner, lender, borrower, polkaVMBridge] = await ethers.getSigners();
    lendingPool = await LendingPool.deploy();
    await lendingPool.deployed();

    // Set PolkaVM bridge address
    await lendingPool.setPolkaVMBridge(polkaVMBridge.address);

    // Mint tokens for testing
    await token.mint(lender.address, ethers.utils.parseEther("1000"));
    await token.mint(borrower.address, ethers.utils.parseEther("1000"));

    // Approve LendingPool to spend tokens
    await token.connect(lender).approve(lendingPool.address, ethers.utils.parseEther("1000"));
    await token.connect(borrower).approve(lendingPool.address, ethers.utils.parseEther("1000"));
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await lendingPool.owner()).to.equal(owner.address);
    });

    it("Should set the right PolkaVM bridge", async function () {
      expect(await lendingPool.polkaVMBridge()).to.equal(polkaVMBridge.address);
    });
  });

  describe("Lender Operations", function () {
    it("Should allow lender to deposit assets", async function () {
      const amount = ethers.utils.parseEther("100");
      await lendingPool.connect(lender).depositLenderAssets(amount);
      const position = await lendingPool.lenderPositions(lender.address);
      expect(position.amount).to.equal(amount);
      expect(position.isLocked).to.equal(false);
    });

    it("Should not allow deposit when position is locked", async function () {
      const amount = ethers.utils.parseEther("100");
      await lendingPool.connect(lender).depositLenderAssets(amount);
      await lendingPool.connect(polkaVMBridge).lockLenderPosition(lender.address);
      
      await expect(
        lendingPool.connect(lender).depositLenderAssets(amount)
      ).to.be.revertedWith("Position is locked");
    });
  });

  describe("Borrower Operations", function () {
    it("Should allow borrower to deposit collateral", async function () {
      const amount = ethers.utils.parseEther("100");
      await lendingPool.connect(borrower).depositCollateral(amount);
      const position = await lendingPool.borrowerPositions(borrower.address);
      expect(position.collateralAmount).to.equal(amount);
      expect(position.isLocked).to.equal(false);
    });

    it("Should not allow deposit when position is locked", async function () {
      const amount = ethers.utils.parseEther("100");
      await lendingPool.connect(borrower).depositCollateral(amount);
      await lendingPool.connect(polkaVMBridge).lockBorrowerPosition(borrower.address);
      
      await expect(
        lendingPool.connect(borrower).depositCollateral(amount)
      ).to.be.revertedWith("Position is locked");
    });
  });

  describe("PolkaVM Bridge Operations", function () {
    it("Should allow bridge to execute borrow", async function () {
      const lendAmount = ethers.utils.parseEther("100");
      const borrowAmount = ethers.utils.parseEther("50");

      await lendingPool.connect(lender).depositLenderAssets(lendAmount);
      await lendingPool.connect(polkaVMBridge).lockLenderPosition(lender.address);
      await lendingPool.connect(borrower).depositCollateral(lendAmount);
      await lendingPool.connect(polkaVMBridge).lockBorrowerPosition(borrower.address);

      await lendingPool.connect(polkaVMBridge).executeBorrow(
        borrower.address,
        lender.address,
        borrowAmount
      );

      const lenderPosition = await lendingPool.lenderPositions(lender.address);
      const borrowerPosition = await lendingPool.borrowerPositions(borrower.address);

      expect(lenderPosition.amount).to.equal(lendAmount.sub(borrowAmount));
      expect(borrowerPosition.borrowedAmount).to.equal(borrowAmount);
    });

    it("Should allow bridge to execute liquidation", async function () {
      const collateralAmount = ethers.utils.parseEther("100");
      const liquidationAmount = ethers.utils.parseEther("50");

      await lendingPool.connect(borrower).depositCollateral(collateralAmount);
      await lendingPool.connect(polkaVMBridge).lockBorrowerPosition(borrower.address);

      await lendingPool.connect(polkaVMBridge).executeLiquidation(
        borrower.address,
        lender.address,
        liquidationAmount
      );

      const borrowerPosition = await lendingPool.borrowerPositions(borrower.address);
      expect(borrowerPosition.collateralAmount).to.equal(collateralAmount.sub(liquidationAmount));
    });
  });
});
