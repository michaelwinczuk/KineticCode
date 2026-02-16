const { expect } = require(\"chai\");\
const { ethers } = require(\"hardhat\");\
const { MerkleTree } = require('merkletreejs');\
const keccak256 = require('keccak256');\
\
function encodeLeaf(account, nonce) {\
  return ethers.utils.solidityKeccak256(\
    ['address', 'uint256'],\
    [account, nonce]\
  );\
}\
\
describe(\"CrossChainNonceManagement v1.2\", function () {\
  let CCNM;\
  let ccnm;\
  let owner;\
  let addr1;\
  let addr2;\
  let addrs;\
  let initialStateRoot;\
  let merkleTree;\
  let leaves;\
  let proof;\
  let validNonce = 1;\
  let invalidNonce = 999;\
\
  beforeEach(async function () {\
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();\
\
    // Generate Merkle Tree\
    leaves = [\
      encodeLeaf(addr1.address, validNonce),\
      encodeLeaf(addr2.address, validNonce),\
    ];\
\
    merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });\
    initialStateRoot = merkleTree.getRoot();\
\
    CCNM = await ethers.getContractFactory(\"CrossChainNonceManagement\");\
    ccnm = await CCNM.deploy(initialStateRoot);\
    await ccnm.deployed();\
\
  });\
\
  describe(\"Deployment\", function () {\
    it(\"Constructor sets initialStateRoot correctly\", async function () {\
      expect(await ccnm.stateRoot()).to.equal(ethers.utils.hexlify(initialStateRoot));\
    });\
  });\
\
  describe(\"State Root Updates\", function () {\
    it(\"updateStateRoot: owner can update\", async function () {\
      const newRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(\"new root\"));\
      await ccnm.updateStateRoot(newRoot);\
      expect(await ccnm.stateRoot()).to.equal(newRoot);\
    });\
\
    it(\"REGRESSION CCNM-003: non-owner cannot call updateStateRoot\", async function () {\
      const newRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(\"new root\"));\
      await expect(ccnm.connect(addr1).updateStateRoot(newRoot)).to.be.revertedWith(\"Ownable: caller is not the owner\");\
    });\
  });\
\
  describe(\"Nonce Consumption\", function () {\
    it(\"consumeNonceWithProof: valid proof with unused nonce succeeds\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const proof = merkleTree.getHexProof(leaf);\
      await expect(ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1)).to.not.be.reverted;\
      expect(await ccnm.isNonceConsumed(addr1.address, validNonce, 1)).to.equal(true);\
    });\
\
    it(\"REGRESSION CCNM-002: nonces segregated by source chainId\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const proof = merkleTree.getHexProof(leaf);\
      await ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1)\
      expect(await ccnm.isNonceConsumed(addr1.address, validNonce, 2)).to.equal(false);\
    });\
\
    it(\"REGRESSION CCNM-001: valid Merkle proof required (not stub)\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const badProof = merkleTree.getHexProof(encodeLeaf(addr2.address, validNonce)); //wrong proof\
      await expect(ccnm.connect(addr1).consumeNonceWithProof(validNonce, badProof, 1)).to.be.revertedWith(\"Invalid Merkle proof.\");\
    });\
\
    it(\"consumeNonceWithProof: invalid proof reverts\", async function () {\
      const invalidLeaf = encodeLeaf(addr1.address, invalidNonce);\
      const invalidProof = merkleTree.getHexProof(invalidLeaf);\
      await expect(ccnm.connect(addr1).consumeNonceWithProof(invalidNonce, invalidProof, 1)).to.be.revertedWith(\"Invalid Merkle proof.\");\
    });\
\
    it(\"consumeNonceWithProof: already consumed nonce reverts\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const proof = merkleTree.getHexProof(leaf);\
      await ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1);\
      await expect(ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1)).to.be.revertedWith(\"Nonce already consumed.\");\
    });\
  });\
\
  describe(\"Nonce Status\", function () {\
    it(\"isNonceConsumed: returns false for unused nonce\", async function () {\
      expect(await ccnm.isNonceConsumed(addr1.address, validNonce, 1)).to.equal(false);\
    });\
\
    it(\"isNonceConsumed: returns true for consumed nonce\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const proof = merkleTree.getHexProof(leaf);\
      await ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1);\
      expect(await ccnm.isNonceConsumed(addr1.address, validNonce, 1)).to.equal(true);\
    });\
  });\
\
  describe(\"Gas Consumption\", function () {\
    it(\"consumeNonceWithProof: measures gas consumption\", async function () {\
      const leaf = encodeLeaf(addr1.address, validNonce);\
      const proof = merkleTree.getHexProof(leaf);\
      const tx = await ccnm.connect(addr1).consumeNonceWithProof(validNonce, proof, 1);\
      const receipt = await tx.wait();\
      console.log(\"Gas used for consumeNonceWithProof:\", receipt.gasUsed.toString());\
    });\
    it(\"updateStateRoot: measures gas consumption\", async function () {\
      const newRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(\"new root\"));\
      const tx = await ccnm.updateStateRoot(newRoot);\
      const receipt = await tx.wait();\
      console.log(\"Gas used for updateStateRoot:\", receipt.gasUsed.toString());\
    });\
  });\
\
});\
