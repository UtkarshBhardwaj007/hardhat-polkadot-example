const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LendingPoolBridge", function () {
  let LendingPoolBridge;
  let lendingPoolBridge;
  let owner;
  let lender;
  let borrower;
  let oracle;
  let wrappedToken;

  beforeEach(async function () {
    // Deploy mock ERC20 token for wrapped token
    const Token = await ethers.getContractFactory("MockERC20");
    wrappedToken = await Token.deploy("Wrapped Token", "WTKN");
    await wrappedToken.deployed();

    // Deploy LendingPoolBridge
    LendingPoolBridge = await ethers.getContractFactory("LendingPoolBridge");
    [owner, lender, borrower, oracle] = await ethers.getSigners();
    lendingPoolBridge = await LendingPoolBridge.deploy(
      oracle.address,
      ethers.constants.AddressZero, // EVM contract address
      wrappedToken.address
    );
    await lendingPoolBridge.deployed();

    // Mint wrapped tokens for testing
    await wrappedToken.mint(lendingPoolBridge.address, ethers.utils.parseEther("10000"));
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await lendingPoolBridge.owner()).to.equal(owner.address);
    });

    it("Should set the right oracle", async function () {
      expect(await lendingPoolBridge.oracle()).to.equal(oracle.address);
    });
  });

  describe("VTL Range Operations", function () {
    it("Should create lender offer with valid VTL range", async function () {
      await lendingPoolBridge.connect(lender).createLenderOffer(
        ethers.utils.parseEther("100"),
        130, // 1.3
        160  // 1.6
      );

      const offer = await lendingPoolBridge.lenderOffers(lender.address);
      expect(offer.amount).to.equal(ethers.utils.parseEther("100"));
      expect(offer.vtlRange.lower).to.equal(130);
      expect(offer.vtlRange.upper).to.equal(160);
      expect(offer.isActive).to.equal(true);
    });

    it("Should create borrower request with valid VTL range", async function () {
      await lendingPoolBridge.connect(borrower).createBorrowerRequest(
        ethers.utils.parseEther("100"), // collateral
        ethers.utils.parseEther("50"),  // requested
        140, // 1.4
        180  // 1.8
      );

      const request = await lendingPoolBridge.borrowerRequests(borrower.address);
      expect(request.collateralAmount).to.equal(ethers.utils.parseEther("100"));
      expect(request.requestedAmount).to.equal(ethers.utils.parseEther("50"));
      expect(request.vtlRange.lower).to.equal(140);
      expect(request.vtlRange.upper).to.equal(180);
      expect(request.isActive).to.equal(true);
    });
  });

  describe("Proof Verification", function () {
    it("Should verify lender proof and generate wrapped tokens", async function () {
      await lendingPoolBridge.connect(lender).createLenderOffer(
        ethers.utils.parseEther("100"),
        130,
        160
      );

      await lendingPoolBridge.verifyProof(
        lender.address,
        true, // isLender
        ethers.utils.parseEther("100"),
        "0x" // mock proof
      );

      const offer = await lendingPoolBridge.lenderOffers(lender.address);
      expect(offer.proofVerified).to.equal(true);
      expect(offer.wrappedTokenBalance).to.equal(ethers.utils.parseEther("100"));
    });

    it("Should verify borrower proof and generate wrapped tokens", async function () {
      await lendingPoolBridge.connect(borrower).createBorrowerRequest(
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("50"),
        140,
        180
      );

      await lendingPoolBridge.verifyProof(
        borrower.address,
        false, // isLender
        ethers.utils.parseEther("100"),
        "0x" // mock proof
      );

      const request = await lendingPoolBridge.borrowerRequests(borrower.address);
      expect(request.proofVerified).to.equal(true);
      expect(request.wrappedCollateralBalance).to.equal(ethers.utils.parseEther("100"));
    });
  });

  describe("Matching and Liquidation", function () {
    beforeEach(async function () {
      // Setup lender
      await lendingPoolBridge.connect(lender).createLenderOffer(
        ethers.utils.parseEther("100"),
        130,
        160
      );
      await lendingPoolBridge.verifyProof(
        lender.address,
        true,
        ethers.utils.parseEther("100"),
        "0x"
      );

      // Setup borrower
      await lendingPoolBridge.connect(borrower).createBorrowerRequest(
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("50"),
        140,
        180
      );
      await lendingPoolBridge.verifyProof(
        borrower.address,
        false,
        ethers.utils.parseEther("100"),
        "0x"
      );

      // Approve bridge to transfer wrapped tokens
      await wrappedToken.connect(lender).approve(
        lendingPoolBridge.address,
        ethers.utils.parseEther("100")
      );
    });

    it("Should match lender and borrower with overlapping VTL", async function () {
      await lendingPoolBridge.findMatch(lender.address, borrower.address);
      
      const liquidityPool = await lendingPoolBridge.liquidityPool(lender.address);
      expect(liquidityPool).to.equal(ethers.utils.parseEther("50")); // matched amount
    });

    it("Should trigger liquidation when collateral ratio is too low", async function () {
      await lendingPoolBridge.connect(oracle).updateCollateralRatio(
        borrower.address,
        130 // 1.3 - below threshold
      );

      const request = await lendingPoolBridge.borrowerRequests(borrower.address);
      expect(request.isActive).to.equal(false); // Position should be deactivated
    });
  });
});
