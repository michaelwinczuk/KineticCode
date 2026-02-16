// We import Chai to use its assert API
const { expect } = require("chai");

// Deploy and control our contract using Hardhat's Ethers integration
const { ethers } = require("hardhat");

describe("SecureMetadataUpdateProtocol", function () {
  let SecureMetadataUpdateProtocol;
  let secureMetadataUpdateProtocol;
  let owner;
  let addr1;
  let addr2;
  const initialMaxURLLength = 256;

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    SecureMetadataUpdateProtocol = await ethers.getContractFactory("SecureMetadataUpdateProtocol");
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy the contract with initial max URL length.
    secureMetadataUpdateProtocol = await SecureMetadataUpdateProtocol.deploy(initialMaxURLLength);
    await secureMetadataUpdateProtocol.deployed();
  });

  describe("Deployment", function () {
    it("Constructor sets maxURLLength and pre-populates allowed domains", async function () {
      expect(await secureMetadataUpdateProtocol.maxURLLength()).to.equal(initialMaxURLLength);
      expect(await secureMetadataUpdateProtocol.isAllowedDomain("arweave.net")).to.equal(true);
      expect(await secureMetadataUpdateProtocol.isAllowedDomain("ipfs.io")).to.equal(true);
      expect(await secureMetadataUpdateProtocol.isAllowedDomain("cloudflare-ipfs.com")).to.equal(true);
    });
  });

  describe("Domain Management", function () {
    it("registerDomain: owner can register, non-owner reverts", async function () {
      const newDomain = "example.com";
      const registerTx = await secureMetadataUpdateProtocol.registerDomain(newDomain);
      const receipt = await registerTx.wait();
      const gasUsed = receipt.gasUsed;
      console.log(`registerDomain gas used: ${gasUsed}`);
      expect(await secureMetadataUpdateProtocol.isAllowedDomain(newDomain)).to.equal(true);

      await expect(secureMetadataUpdateProtocol.connect(addr1).registerDomain(newDomain)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("unregisterDomain: owner can unregister, non-owner reverts", async function () {
      const domainToUnregister = "arweave.net";
      const unregisterTx = await secureMetadataUpdateProtocol.unregisterDomain(domainToUnregister);
      const receipt = await unregisterTx.wait();
      const gasUsed = receipt.gasUsed;
      console.log(`unregisterDomain gas used: ${gasUsed}`);

      expect(await secureMetadataUpdateProtocol.isAllowedDomain(domainToUnregister)).to.equal(false);
      await expect(secureMetadataUpdateProtocol.connect(addr1).unregisterDomain(domainToUnregister)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("setMaxURLLength: owner can set, non-owner reverts", async function () {
      const newMaxURLLength = 512;
      const setMaxTx = await secureMetadataUpdateProtocol.setMaxURLLength(newMaxURLLength);
      const receipt = await setMaxTx.wait();
      const gasUsed = receipt.gasUsed;
      console.log(`setMaxURLLength gas used: ${gasUsed}`);

      expect(await secureMetadataUpdateProtocol.maxURLLength()).to.equal(newMaxURLLength);

      await expect(secureMetadataUpdateProtocol.connect(addr1).setMaxURLLength(newMaxURLLength)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
    });
  });

  describe("URL Sanitization", function () {
    it("sanitizeAnimationURL: valid arweave.net URL passes", async function () {
      const validArweaveURL = "ar://ewi6UNjJJf4Y-cEq481-HBPjHn8QmPGLqEwJq-WtCc0";
      expect(await secureMetadataUpdateProtocol.sanitizeAnimationURL(validArweaveURL)).to.equal(validArweaveURL);
    });

    it("sanitizeAnimationURL: valid ipfs.io URL passes", async function () {
      const validIpfsURL = "ipfs://QmVUNVWJapRgFfFVj8JBj9kXoP72i8266NM7QQWjBjL9m"
      expect(await secureMetadataUpdateProtocol.sanitizeAnimationURL(validIpfsURL)).to.equal(validIpfsURL);
    });

    it("sanitizeAnimationURL: unregistered domain reverts", async function () {
      const invalidURL = "https://evil.com/metadata.json";
      await expect(secureMetadataUpdateProtocol.sanitizeAnimationURL(invalidURL)).to.be.revertedWith("Domain not allowed");
    });

    it("sanitizeAnimationURL: URL exceeding maxURLLength reverts", async function () {
      const longURL = "ar://" + "a".repeat(initialMaxURLLength + 1);
      await expect(secureMetadataUpdateProtocol.sanitizeAnimationURL(longURL)).to.be.revertedWith("URL exceeds max length");
    });

    it("sanitizeAnimationURL: strips query parameters from URL", async function () {
      const urlWithParams = "https://arweave.net/ewi6UNjJJf4Y-cEq481-HBPjHn8QmPGLqEwJq-WtCc0?param1=value1&param2=value2";
      const expectedURL = "https://arweave.net/ewi6UNjJJf4Y-cEq481-HBPjHn8QmPGLqEwJq-WtCc0";
      expect(await secureMetadataUpdateProtocol.sanitizeAnimationURL(urlWithParams)).to.equal(expectedURL);
    });
  });

  describe("Hostname Extraction", function () {
    it("extractHostname: correctly extracts from https:// URL", async function () {
      const url = "https://www.example.com/path";
      expect(await secureMetadataUpdateProtocol.extractHostname(url)).to.equal("www.example.com");
    });

    it("extractHostname: correctly extracts from ar:// URL", async function () {
      const url = "ar://ewi6UNjJJf4Y-cEq481-HBPjHn8QmPGLqEwJq-WtCc0";
      expect(await secureMetadataUpdateProtocol.extractHostname(url)).to.equal("arweave.net");
    });
  });

  describe("Regression Tests", function () {
    it("REGRESSION SMUP-001: unregistered account cannot call registerDomain", async function () {
      await expect(secureMetadataUpdateProtocol.connect(addr1).registerDomain("hacker.com")).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("REGRESSION SMUP-002: https://evil.com/payload.js is rejected by domain check", async function () {
      const evilURL = "https://evil.com/payload.js";
      await expect(secureMetadataUpdateProtocol.sanitizeAnimationURL(evilURL)).to.be.revertedWith("Domain not allowed");
    });

    it("REGRESSION SMUP-003: URL at maxURLLength passes, URL at maxURLLength+1 reverts", async function () {
      const maxLengthURL = "ar://" + "a".repeat(initialMaxURLLength);
      const tooLongURL = "ar://" + "a".repeat(initialMaxURLLength + 1);

      expect(await secureMetadataUpdateProtocol.sanitizeAnimationURL(maxLengthURL)).to.equal(maxLengthURL);
      await expect(secureMetadataUpdateProtocol.sanitizeAnimationURL(tooLongURL)).to.be.revertedWith("URL exceeds max length");
    });
  });
});
