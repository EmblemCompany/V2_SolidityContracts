// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {EmblemVaultDiamond} from "../src/EmblemVaultDiamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {EmblemVaultCoreFacet} from "../src/facets/EmblemVaultCoreFacet.sol";
import {EmblemVaultUnvaultFacet} from "../src/facets/EmblemVaultUnvaultFacet.sol";
import {EmblemVaultMintFacet} from "../src/facets/EmblemVaultMintFacet.sol";
import {EmblemVaultCollectionFacet} from "../src/facets/EmblemVaultCollectionFacet.sol";
import {EmblemVaultInitFacet} from "../src/facets/EmblemVaultInitFacet.sol";
import {LibErrors} from "../src/libraries/LibErrors.sol";
import {LibSignature} from "../src/libraries/LibSignature.sol";
import {VaultBeacon, ERC721VaultBeacon, ERC1155VaultBeacon} from "../src/beacon/VaultBeacon.sol";
import {ERC721VaultImplementation} from "../src/implementations/ERC721VaultImplementation.sol";
import {ERC1155VaultImplementation} from "../src/implementations/ERC1155VaultImplementation.sol";
import {VaultCollectionFactory} from "../src/factories/VaultCollectionFactory.sol";
import "./mocks/MockERC20.sol";

contract UnvaultBatchOperationsTest is Test {
    // Diamond components
    EmblemVaultDiamond diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    OwnershipFacet ownershipFacet;
    EmblemVaultCoreFacet vaultCoreFacet;
    EmblemVaultUnvaultFacet unvaultFacet;
    EmblemVaultMintFacet mintFacet;
    EmblemVaultCollectionFacet collectionFacet;
    EmblemVaultInitFacet initFacet;

    // Test components
    MockERC20 paymentToken;
    address nftCollection;
    VaultCollectionFactory factory;
    ERC721VaultImplementation erc721Implementation;
    ERC1155VaultImplementation erc1155Implementation;
    ERC721VaultBeacon erc721Beacon;
    ERC1155VaultBeacon erc1155Beacon;

    // Test addresses
    address owner = address(this);
    address user1 = address(0x1);
    uint256 constant witnessPrivateKey =
        0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 constant nonWitnessPrivateKey =
        0x2234567890123456789012345678901234567890123456789012345678901234;
    address witness;

    // Test batch sizes
    uint256[] batchSizes = [1, 5, 10, 20];
    uint256 constant MAX_BATCH_SIZE = 45;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        // Derive witness address
        witness = vm.addr(witnessPrivateKey);

        // Deploy mock contracts
        paymentToken = new MockERC20("Payment Token", "PAY");

        // Deploy implementations
        erc721Implementation = new ERC721VaultImplementation();
        erc1155Implementation = new ERC1155VaultImplementation();

        // Deploy beacons
        erc721Beacon = new ERC721VaultBeacon(address(erc721Implementation));
        erc1155Beacon = new ERC1155VaultBeacon(address(erc1155Implementation));

        // Deploy facets
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        vaultCoreFacet = new EmblemVaultCoreFacet();
        unvaultFacet = new EmblemVaultUnvaultFacet();
        mintFacet = new EmblemVaultMintFacet();
        collectionFacet = new EmblemVaultCollectionFacet();
        initFacet = new EmblemVaultInitFacet();

        // Deploy Diamond
        diamond = new EmblemVaultDiamond(owner, address(diamondCutFacet));

        // Build cut struct
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](7);

        // Add all facets
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("DiamondLoupeFacet")
        });

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("OwnershipFacet")
        });

        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(vaultCoreFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("VaultCoreFacet")
        });

        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(unvaultFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("UnvaultFacet")
        });

        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(mintFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("MintFacet")
        });

        cut[5] = IDiamondCut.FacetCut({
            facetAddress: address(collectionFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("CollectionFacet")
        });

        cut[6] = IDiamondCut.FacetCut({
            facetAddress: address(initFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFacetSelectors("InitFacet")
        });

        // Add facets to diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        // Initialize diamond
        EmblemVaultInitFacet(address(diamond)).initialize(owner);

        // Configure diamond
        vm.startPrank(owner);
        EmblemVaultCoreFacet(address(diamond)).setRecipientAddress(address(this));
        EmblemVaultCoreFacet(address(diamond)).addWitness(witness);
        vm.stopPrank();

        // Deploy factory
        factory = new VaultCollectionFactory(
            address(erc721Beacon), address(erc1155Beacon), address(diamond)
        );

        // Set factory in diamond through both facets
        vm.startPrank(owner);
        EmblemVaultCoreFacet(address(diamond)).setVaultFactory(address(factory));
        EmblemVaultCollectionFacet(address(diamond)).setCollectionFactory(address(factory));
        vm.stopPrank();

        // Create test collection
        vm.prank(address(diamond));
        nftCollection = factory.createERC721Collection("Test NFT", "NFT");

        // Setup test environment
        vm.deal(user1, 1000 ether);
        paymentToken.mint(user1, 1000 ether);

        // Enable unvaulting
        vm.prank(owner);
        EmblemVaultUnvaultFacet(address(diamond)).setUnvaultingEnabled(true);
    }

    function testBatchUnvault() public {
        uint256 batchSize = 5;
        uint256 basePrice = 0.1 ether;

        // First mint some tokens to unvault
        uint256[] memory prices = new uint256[](batchSize);
        uint256[] memory tokenIds = new uint256[](batchSize);
        uint256[] memory nonces = new uint256[](batchSize);
        bytes[] memory signatures = new bytes[](batchSize);
        uint256[][] memory serialNumbers = new uint256[][](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);

        // Fill arrays with test data
        uint256 totalPrice = 0;
        for (uint256 j = 0; j < batchSize; j++) {
            prices[j] = basePrice;
            tokenIds[j] = j + 1;
            nonces[j] = j + 1;
            amounts[j] = 1;
            signatures[j] = createSignature(
                nftCollection,
                address(0),
                basePrice,
                user1,
                tokenIds[j],
                nonces[j],
                amounts[j],
                witnessPrivateKey
            );
            serialNumbers[j] = new uint256[](0);
            totalPrice += basePrice;
        }

        // Mint tokens
        vm.startPrank(user1);
        // Create an array with a single NFT address repeated for each token
        address[] memory nftAddresses = new address[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            nftAddresses[i] = nftCollection;
        }

        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;

        EmblemVaultMintFacet.BatchBuyParams memory mintParams = EmblemVaultMintFacet.BatchBuyParams({
            nftAddresses: nftAddresses,
            payment: address(0),
            prices: prices,
            to: user1,
            tokenIds: tokenIds,
            nonces: nonces,
            signatures: signatures,
            serialNumbers: serialNumbers,
            amounts: amounts,
            timestamp: timestamp
        });

        EmblemVaultMintFacet(address(diamond)).batchBuyWithSignedPrice{value: totalPrice}(
            mintParams
        );
        vm.stopPrank();

        // Prepare unvault parameters
        address[] memory unvaultNftAddresses = new address[](batchSize);
        address[] memory payments = new address[](batchSize);
        uint256[] memory unvaultPrices = new uint256[](batchSize);
        uint256[] memory unvaultNonces = new uint256[](batchSize);
        bytes[] memory unvaultSignatures = new bytes[](batchSize);

        for (uint256 j = 0; j < batchSize; j++) {
            unvaultNftAddresses[j] = nftCollection;
            payments[j] = address(0);
            unvaultPrices[j] = basePrice;
            unvaultNonces[j] = batchSize + j + 1; // Use different nonces than mint
            unvaultSignatures[j] = createUnvaultSignature(
                nftCollection,
                address(0),
                basePrice,
                user1,
                tokenIds[j],
                unvaultNonces[j],
                1, // amount is always 1 for unvaulting
                witnessPrivateKey
            );
        }

        // Test batch unvault (no approval needed - diamond can burn directly)
        vm.startPrank(user1);
        uint256 gasStart = gasleft();

        // Use timestamp 0 for signature verification in tests
        uint256 unvaultTimestamp = 0;

        EmblemVaultUnvaultFacet.BatchUnvaultParams memory params = EmblemVaultUnvaultFacet
            .BatchUnvaultParams({
            nftAddresses: unvaultNftAddresses,
            tokenIds: tokenIds,
            nonces: unvaultNonces,
            payments: payments,
            prices: unvaultPrices,
            signatures: unvaultSignatures,
            timestamp: unvaultTimestamp
        });

        EmblemVaultUnvaultFacet(address(diamond)).batchUnvaultWithSignedPrice{value: totalPrice}(
            params
        );

        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        // Verify state
        for (uint256 j = 0; j < batchSize; j++) {
            assertTrue(
                EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(
                    nftCollection, tokenIds[j]
                ),
                "Token should be unvaulted"
            );
            assertEq(
                EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(
                    nftCollection, tokenIds[j]
                ),
                user1,
                "Unvaulter should be user1"
            );
        }

        // Log gas usage
        emit log_named_uint("Gas used for batch unvault", gasUsed);
        emit log_named_uint("Gas per operation", gasUsed / batchSize);
    }

    function testBatchSizeLimitEnforcement() public {
        uint256 basePrice = 0.1 ether;
        uint256 oversizedBatch = MAX_BATCH_SIZE + 1;

        // Prepare batch parameters
        address[] memory nftAddresses = new address[](oversizedBatch);
        address[] memory payments = new address[](oversizedBatch);
        uint256[] memory prices = new uint256[](oversizedBatch);
        uint256[] memory tokenIds = new uint256[](oversizedBatch);
        uint256[] memory nonces = new uint256[](oversizedBatch);
        bytes[] memory signatures = new bytes[](oversizedBatch);

        // Fill arrays with test data
        for (uint256 j = 0; j < oversizedBatch; j++) {
            nftAddresses[j] = nftCollection;
            payments[j] = address(0);
            prices[j] = basePrice;
            tokenIds[j] = j + 1;
            nonces[j] = j + 1;
            signatures[j] = createUnvaultSignature(
                nftCollection,
                address(0),
                basePrice,
                user1,
                tokenIds[j],
                nonces[j],
                1,
                witnessPrivateKey
            );
        }

        // Test batch unvaulting with oversized batch
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibErrors.BatchSizeExceeded.selector, oversizedBatch, MAX_BATCH_SIZE
            )
        );

        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;

        EmblemVaultUnvaultFacet.BatchUnvaultParams memory params = EmblemVaultUnvaultFacet
            .BatchUnvaultParams({
            nftAddresses: nftAddresses,
            tokenIds: tokenIds,
            nonces: nonces,
            payments: payments,
            prices: prices,
            signatures: signatures,
            timestamp: timestamp
        });

        EmblemVaultUnvaultFacet(address(diamond)).batchUnvaultWithSignedPrice(params);
        vm.stopPrank();
    }

    function testERC1155UnvaultWithSerialNumbers() public {
        uint256 basePrice = 0.1 ether;
        uint256 tokenId = 1;

        // Create ERC1155 collection
        vm.prank(address(diamond));
        address erc1155Collection = factory.createERC1155Collection("https://api.test.com/");

        // Prepare serial numbers for minting
        uint256[] memory serialNumbers = new uint256[](3);
        serialNumbers[0] = 100; // First serial
        serialNumbers[1] = 200; // Second serial
        serialNumbers[2] = 300; // Third serial (will be last in LIFO)

        // Mint ERC1155 tokens with serial numbers
        vm.prank(address(diamond));
        ERC1155VaultImplementation(erc1155Collection).mintWithSerial(
            user1, tokenId, 3, serialNumbers
        );

        // Verify initial state
        assertEq(ERC1155VaultImplementation(erc1155Collection).balanceOf(user1, tokenId), 3);

        // Check serial ownership
        uint256[] memory userSerials =
            ERC1155VaultImplementation(erc1155Collection).getSerials(user1, tokenId);
        assertEq(userSerials.length, 3);
        assertEq(userSerials[0], 100);
        assertEq(userSerials[1], 200);
        assertEq(userSerials[2], 300);

        // Test unvaulting - should use LIFO (Last In, First Out)
        // The last serial (index 2, serial 300) should be unvaulted first
        uint256 lastSerialIndex =
            ERC1155VaultImplementation(erc1155Collection).balanceOf(user1, tokenId) - 1;
        uint256 expectedSerialToUnvault = ERC1155VaultImplementation(erc1155Collection)
            .getSerialByOwnerAtIndex(user1, tokenId, lastSerialIndex);

        console.log("Expected serial to unvault (LIFO):", expectedSerialToUnvault);
        assertEq(expectedSerialToUnvault, 300, "Should unvault the last serial (LIFO)");

        // Create signature for unvaulting
        bytes memory signature = createUnvaultSignature(
            erc1155Collection,
            address(0),
            basePrice,
            user1,
            tokenId,
            12_345, // nonce
            1, // amount is always 1 for unvaulting
            witnessPrivateKey
        );

        // Test unvaulting (no approval needed - diamond can burn directly)
        vm.startPrank(user1);

        EmblemVaultUnvaultFacet(address(diamond)).unvaultWithSignedPrice{value: basePrice}(
            erc1155Collection,
            tokenId,
            12_345, // nonce
            address(0), // ETH payment
            basePrice,
            signature,
            0 // timestamp for tests
        );

        vm.stopPrank();

        // Verify post-unvault state
        assertEq(
            ERC1155VaultImplementation(erc1155Collection).balanceOf(user1, tokenId),
            2,
            "Should have 2 tokens left after unvaulting 1"
        );

        // Verify the unvaulted serial is tracked by serial number, not token ID
        assertTrue(
            EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(
                erc1155Collection, expectedSerialToUnvault
            ),
            "The specific serial number should be marked as unvaulted"
        );

        // Verify the unvaulter is recorded correctly
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(
                erc1155Collection, expectedSerialToUnvault
            ),
            user1,
            "User1 should be recorded as the unvaulter for this serial"
        );

        // Verify remaining serials are still owned by user1
        uint256[] memory remainingSerials =
            ERC1155VaultImplementation(erc1155Collection).getSerials(user1, tokenId);
        assertEq(remainingSerials.length, 2, "Should have 2 serials remaining");

        // The remaining serials should be 100 and 200 (since 300 was removed via LIFO)
        assertEq(remainingSerials[0], 100);
        assertEq(remainingSerials[1], 200);

        // Test unvaulting another token - should unvault serial 200 next (LIFO)
        bytes memory signature2 = createUnvaultSignature(
            erc1155Collection,
            address(0),
            basePrice,
            user1,
            tokenId,
            12_346, // different nonce
            1,
            witnessPrivateKey
        );

        vm.startPrank(user1);
        EmblemVaultUnvaultFacet(address(diamond)).unvaultWithSignedPrice{value: basePrice}(
            erc1155Collection, tokenId, 12_346, address(0), basePrice, signature2, 0
        );
        vm.stopPrank();

        // Verify second unvault
        assertEq(
            ERC1155VaultImplementation(erc1155Collection).balanceOf(user1, tokenId),
            1,
            "Should have 1 token left"
        );

        // Should have unvaulted serial 200 (the new "last" serial)
        assertTrue(
            EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(erc1155Collection, 200),
            "Serial 200 should be marked as unvaulted"
        );

        // Verify only serial 100 remains
        uint256[] memory finalSerials =
            ERC1155VaultImplementation(erc1155Collection).getSerials(user1, tokenId);
        assertEq(finalSerials.length, 1, "Should have 1 serial remaining");
        assertEq(finalSerials[0], 100, "Only serial 100 should remain");

        console.log("ERC1155 LIFO unvaulting behavior verified:");
        console.log("   - First unvault: Serial 300 (last in array)");
        console.log("   - Second unvault: Serial 200 (new last in array)");
        console.log("   - Remaining: Serial 100");
    }

    // Helper function to create signature for minting
    function createSignature(
        address _nftAddress,
        address _payment,
        uint256 _price,
        address _to,
        uint256 _tokenId,
        uint256 _nonce,
        uint256 _amount,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        // Create empty array for serialNumbers
        uint256[] memory serialNumbers = new uint256[](0);

        // Use LibSignature to generate hash
        bytes32 hash = LibSignature.getStandardSignatureHash(
            _nftAddress,
            _payment,
            _price,
            _to,
            _tokenId,
            _nonce,
            _amount,
            serialNumbers,
            0, // timestamp
            block.chainid
        );

        // Sign with Ethereum prefix
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, prefixedHash);
        return abi.encodePacked(r, s, v);
    }

    // Helper function to create signature for unvaulting
    function createUnvaultSignature(
        address _nftAddress,
        address _payment,
        uint256 _price,
        address _to,
        uint256 _tokenId,
        uint256 _nonce,
        uint256 _amount,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        // Create empty array for serialNumbers
        uint256[] memory serialNumbers = new uint256[](0);

        // Use LibSignature to generate hash
        bytes32 hash = LibSignature.getStandardSignatureHash(
            _nftAddress,
            _payment,
            _price,
            _to,
            _tokenId,
            _nonce,
            _amount,
            serialNumbers,
            0, // timestamp
            block.chainid
        );

        // Sign with Ethereum prefix
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, prefixedHash);
        return abi.encodePacked(r, s, v);
    }

    // Helper function to get function selectors for each facet
    function getFacetSelectors(string memory facetName)
        internal
        pure
        returns (bytes4[] memory selectors)
    {
        if (keccak256(bytes(facetName)) == keccak256(bytes("DiamondLoupeFacet"))) {
            selectors = new bytes4[](5);
            selectors[0] = DiamondLoupeFacet.facets.selector;
            selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
            selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            selectors[3] = DiamondLoupeFacet.getFacetAddress.selector;
            selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("OwnershipFacet"))) {
            selectors = new bytes4[](2);
            selectors[0] = OwnershipFacet.transferOwnership.selector;
            selectors[1] = OwnershipFacet.owner.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("VaultCoreFacet"))) {
            selectors = new bytes4[](12);
            selectors[0] = EmblemVaultCoreFacet.lockVault.selector;
            selectors[1] = EmblemVaultCoreFacet.unlockVault.selector;
            selectors[2] = EmblemVaultCoreFacet.isVaultLocked.selector;
            selectors[3] = EmblemVaultCoreFacet.addWitness.selector;
            selectors[4] = EmblemVaultCoreFacet.removeWitness.selector;
            selectors[5] = EmblemVaultCoreFacet.setRecipientAddress.selector;
            selectors[6] = EmblemVaultCoreFacet.setMetadataBaseUri.selector;
            selectors[7] = EmblemVaultCoreFacet.isWitness.selector;
            selectors[8] = EmblemVaultCoreFacet.getWitnessCount.selector;
            selectors[9] = EmblemVaultCoreFacet.getCoreVersion.selector;
            selectors[10] = EmblemVaultCoreFacet.setVaultFactory.selector;
            selectors[11] = EmblemVaultCoreFacet.getVaultFactory.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("UnvaultFacet"))) {
            selectors = new bytes4[](9);
            selectors[0] = EmblemVaultUnvaultFacet.getUnvaultVersion.selector;
            selectors[1] = EmblemVaultUnvaultFacet.setUnvaultingEnabled.selector;
            selectors[2] = EmblemVaultUnvaultFacet.setBurnAddress.selector;
            selectors[3] = EmblemVaultUnvaultFacet.unvault.selector;
            selectors[4] = EmblemVaultUnvaultFacet.batchUnvaultWithSignedPrice.selector;
            selectors[5] = EmblemVaultUnvaultFacet.unvaultWithSignedPrice.selector;
            selectors[6] = EmblemVaultUnvaultFacet.isTokenUnvaulted.selector;
            selectors[7] = EmblemVaultUnvaultFacet.getTokenUnvaulter.selector;
            selectors[8] = EmblemVaultUnvaultFacet.getCollectionUnvaultCount.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("MintFacet"))) {
            selectors = new bytes4[](3);
            selectors[0] = EmblemVaultMintFacet.buyWithSignedPrice.selector;
            selectors[1] = EmblemVaultMintFacet.batchBuyWithSignedPrice.selector;
            selectors[2] = EmblemVaultMintFacet.getMintVersion.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("CollectionFacet"))) {
            selectors = new bytes4[](13);
            selectors[0] = EmblemVaultCollectionFacet.setCollectionFactory.selector;
            selectors[1] = EmblemVaultCollectionFacet.createVaultCollection.selector;
            selectors[2] = EmblemVaultCollectionFacet.upgradeCollectionImplementation.selector;
            selectors[3] = EmblemVaultCollectionFacet.getCollectionImplementation.selector;
            selectors[4] = EmblemVaultCollectionFacet.getCollectionBeacon.selector;
            selectors[5] = EmblemVaultCollectionFacet.isCollection.selector;
            selectors[6] = EmblemVaultCollectionFacet.getCollectionFactory.selector;
            selectors[7] = EmblemVaultCollectionFacet.setCollectionBaseURI.selector;
            selectors[8] = EmblemVaultCollectionFacet.setCollectionURI.selector;
            selectors[9] = EmblemVaultCollectionFacet.getCollectionVersion.selector;
            selectors[10] = EmblemVaultCollectionFacet.setCollectionOwner.selector;
            selectors[11] = EmblemVaultCollectionFacet.getCollectionOwner.selector;
            selectors[12] = EmblemVaultCollectionFacet.getCollectionType.selector;
        } else if (keccak256(bytes(facetName)) == keccak256(bytes("InitFacet"))) {
            selectors = new bytes4[](6);
            selectors[0] = EmblemVaultInitFacet.initialize.selector;
            selectors[1] = EmblemVaultInitFacet.isInitialized.selector;
            selectors[2] = EmblemVaultInitFacet.getInterfaceIds.selector;
            selectors[3] = EmblemVaultInitFacet.getConfiguration.selector;
            selectors[4] = EmblemVaultInitFacet.getInitializationDetails.selector;
            selectors[5] = EmblemVaultInitFacet.getInitVersion.selector;
        }
    }
}
