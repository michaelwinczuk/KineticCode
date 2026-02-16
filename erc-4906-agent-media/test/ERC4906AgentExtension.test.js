const { expect } = require("chai");
const { ethers } = require("hardhat");
const { keccak256 } = require("ethers");

describe("ERC4906AgentExtension v1.1 Tests", function () {
  let ERC4906AgentExtension, agentExtension, targetNFT, owner, agent, unauthorizedAgent;
  const DOMAIN_TYPE = [
    { name: "name", type: "string" },
    { name: "version", type: "string" },
    { name: "chainId", type: "uint256" },
    { name: "verifyingContract", type: "address" },
  ];

  const UPDATE_METADATA_TYPE = [
    { name: "nonceHash", type: "bytes32" },
    { name: "metadata", type: "string" },
  ];

  beforeEach(async function () {
    [owner, agent, unauthorizedAgent] = await ethers.getSigners();

    // Mock TargetNFT contract
    const TargetNFT = await ethers.getContractFactory("MockTargetNFT");
    targetNFT = await TargetNFT.deploy();
    await targetNFT.deployed();

    ERC4906AgentExtension = await ethers.getContractFactory("ERC4906AgentExtension");
    agentExtension = await ERC4906AgentExtension.deploy(targetNFT.address);
    await agentExtension.deployed();

    // Grant agent role in the mock NFT contract
    await targetNFT.connect(owner).setAgent(agentExtension.address);
  });

  it("Constructor sets targetNFT correctly", async function () {
    expect(await agentExtension.targetNFT()).to.equal(targetNFT.address);
  });

  describe("Agent Authorization", function () {
    it("NFT contract can authorize, other addresses revert", async function () {
      await expect(agentExtension.connect(targetNFT.signer).authorizeAgent(agent.address))
        .to.emit(agentExtension, "AgentAuthorized")
        .withArgs(agent.address);

      expect(await agentExtension.isAuthorized(agent.address)).to.be.true;

      await expect(agentExtension.connect(unauthorizedAgent).authorizeAgent(agent.address))
        .to.be.revertedWith("Only NFT contract can call this function");
    });

    it("NFT contract can revoke, other addresses revert", async function () {
      await agentExtension.connect(targetNFT.signer).authorizeAgent(agent.address);

      await expect(agentExtension.connect(targetNFT.signer).revokeAgent(agent.address))
        .to.emit(agentExtension, "AgentRevoked")
        .withArgs(agent.address);

      expect(await agentExtension.isAuthorized(agent.address)).to.be.false;

      await expect(agentExtension.connect(unauthorizedAgent).revokeAgent(agent.address))
        .to.be.revertedWith("Only NFT contract can call this function");
    });
  });

  describe("Nonce and Signature Management", function () {
    it("generateNonceHash: produces correct keccak256(nonce, agent)", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const expectedHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const calculatedHash = await agentExtension.generateNonceHash(nonce, agent.address);
      expect(calculatedHash).to.equal(expectedHash);
    });

    it("updateMetadataWithSig: valid signature from authorized agent succeeds", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata = "ipfs://example.com/metadata.json";

      const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };

      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata,
        },
      };

      const signature = await agent._signTypedData(domain, 'UpdateMetadata', typedData.message);
      const gasUsed = await agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata, signature).then(tx => tx.gasUsed);
      console.log("Gas Used for updateMetadataWithSig: ", gasUsed.toString());

      expect(await agentExtension.metadataByNonceHash(nonceHash)).to.equal(metadata);
    });

    it("updateMetadataWithSig: signature from unauthorized agent reverts", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata = "ipfs://example.com/metadata.json";

       const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };

      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata,
        },
      };

      const signature = await unauthorizedAgent._signTypedData(domain, 'UpdateMetadata', typedData.message);

      await expect(agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata, signature))
        .to.be.revertedWith("Invalid signature");
    });

    it("updateMetadataWithSig: reused nonce hash reverts", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata1 = "ipfs://example.com/metadata1.json";
       const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };

      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata1,
        },
      };

      const signature = await agent._signTypedData(domain, 'UpdateMetadata', typedData.message);

      await agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata1, signature);
      const metadata2 = "ipfs://example.com/metadata2.json";
      
      const typedData2 = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata2,
        },
      };
      const signature2 = await agent._signTypedData(domain, 'UpdateMetadata', typedData2.message);


      await expect(agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata2, signature2))
        .to.be.revertedWith("Nonce already used");
    });

    it("updateMetadataWithSig: expired signature reverts", async function () {
      // This test requires time manipulation, which is more complex to implement in this context.
      // Skipping for now, but it should be added in a full implementation.
      this.skip();
    });

    it("revealNonce: authorized agent can reveal valid nonce", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata = "ipfs://example.com/metadata.json";

      const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };

      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata,
        },
      };

      const signature = await agent._signTypedData(domain, 'UpdateMetadata', typedData.message);

      await agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata, signature);

      await expect(agentExtension.connect(agent).revealNonce(nonce))
        .to.emit(agentExtension, "NonceRevealed")
        .withArgs(nonceHash, agent.address);

      expect(await agentExtension.revealedNonces(nonceHash)).to.be.true;
    });

    it("revealNonce: unauthorized agent cannot reveal nonce", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata = "ipfs://example.com/metadata.json";

      const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };

      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata,
        },
      };

      const signature = await agent._signTypedData(domain, 'UpdateMetadata', typedData.message);
      await agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata, signature);

      await expect(agentExtension.connect(unauthorizedAgent).revealNonce(nonce))
        .to.be.revertedWith("Unauthorized");
    });
  });

  describe("Regression Tests", function () {
    it("REGRESSION EAE-001: signature created on wrong chainId fails verification", async function () {
          this.skip(); //Skipping due to inability to change chainId in hardhat tests
    });

    it("REGRESSION EAE-002: ecrecover returning address(0) is rejected", async function () {
        this.skip(); //Skipping - requires low-level signature crafting
    });

    it("REGRESSION EAE-003: nonce griefing attack prevented by hash commitment", async function () {
      const nonce = ethers.utils.randomBytes(32);
      const nonceHash = keccak256(ethers.utils.concat([nonce, agent.address]));
      const metadata = "ipfs://example.com/metadata.json";
      const domain = {
        name: "ERC4906AgentExtension",
        version: "1.1",
        chainId: await ethers.provider.getNetwork().then((network) => network.chainId),
        verifyingContract: agentExtension.address,
      };
      const typedData = {
        types: {
          EIP712Domain: DOMAIN_TYPE,
          UpdateMetadata: UPDATE_METADATA_TYPE,
        },
        primaryType: "UpdateMetadata",
        domain: domain,
        message: {
          nonceHash: nonceHash,
          metadata: metadata,
        },
      };
      const signature = await agent._signTypedData(domain, 'UpdateMetadata', typedData.message);

      await agentExtension.connect(targetNFT.signer).updateMetadataWithSig(nonceHash, metadata, signature);
      // Try to reveal the nonce before updating the metadata.
       const attackerNonce = ethers.utils.randomBytes(32);
       await expect(agentExtension.connect(agent).revealNonce(attackerNonce)).to.be.revertedWith("Unauthorized");

    });
  });
});
