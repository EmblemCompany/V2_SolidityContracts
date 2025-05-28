// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./DiamondVault.t.sol";
import "../src/interfaces/IERC1155.sol";
import "../src/libraries/LibEmblemVaultStorage.sol";
import "../src/libraries/LibErrors.sol";

contract UnvaultTrackingTest is DiamondVaultTest {
    // Events
    event UnvaultingEnabled(bool enabled);
    event BurnAddressUpdated(address indexed addr, bool isBurn);

    error TokenMappingNotFound();

    function setUp() public override {
        super.setUp();
    }

    function testUnvaultingEnabledByDefault() public {
        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2, // new token ID
            2, // new nonce
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Approve diamond
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);
        vm.stopPrank();

        // Verify token was burned
        vm.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        ERC721VaultImplementation(nftCollection).ownerOf(2);
    }

    function testDisableUnvaulting() public {
        // Disable unvaulting
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit UnvaultingEnabled(false);
        EmblemVaultUnvaultFacet(address(diamond)).setUnvaultingEnabled(false);
        vm.stopPrank();

        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Approve diamond to manage tokens
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

        vm.expectRevert(LibEmblemVaultStorage.UnvaultingDisabled.selector);
        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);
        vm.stopPrank();
    }

    function testPreventDoubleUnvault() public {
        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Approve for all to diamond
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);

        // Second unvault should fail with TokenMappingNotFound since the token was burned
        vm.expectRevert(TokenMappingNotFound.selector);
        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);
        vm.stopPrank();
    }

    function testBurnAddressManagement() public {
        address burnAddr = address(0x123);

        // Add burn address
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit BurnAddressUpdated(burnAddr, true);
        EmblemVaultUnvaultFacet(address(diamond)).setBurnAddress(burnAddr, true);

        // Remove burn address
        vm.expectEmit(true, true, true, true);
        emit BurnAddressUpdated(burnAddr, false);
        EmblemVaultUnvaultFacet(address(diamond)).setBurnAddress(burnAddr, false);
        vm.stopPrank();
    }

    function testRevertSetBurnAddressNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.Unauthorized.selector, user1));
        EmblemVaultUnvaultFacet(address(diamond)).setBurnAddress(address(0x123), true);
        vm.stopPrank();
    }

    function testRevertSetUnvaultingEnabledNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(LibErrors.Unauthorized.selector, user1));
        EmblemVaultUnvaultFacet(address(diamond)).setUnvaultingEnabled(false);
        vm.stopPrank();
    }

    function testUnvaultStatusTracking() public {
        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Approve diamond
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

        // Check initial unvault status
        assertFalse(EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(nftCollection, 2));

        // Unvault token
        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);
        vm.stopPrank();

        // Verify unvault status and unvaulter
        assertTrue(EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(nftCollection, 2));
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(nftCollection, 2),
            tokenHolder
        );
    }

    function testERC1155UnvaultWithSerialNumber() public {
        // Create ERC1155 collection through the factory
        vm.startPrank(owner);
        EmblemVaultCollectionFacet(address(diamond)).setCollectionFactory(address(factory));
        vm.stopPrank();

        vm.prank(address(diamond));
        address erc1155Collection = factory.createERC1155Collection("testuri.com/");

        // Create signature for minting with serial number
        uint256[] memory serialNumbers = new uint256[](1);
        serialNumbers[0] = 12_345;

        // Create signature from witness
        bytes32 hash = LibSignature.getStandardSignatureHash(
            erc1155Collection,
            address(0),
            1 ether,
            tokenHolder,
            1,
            100,
            1,
            serialNumbers,
            0, // timestamp
            block.chainid
        );

        // Sign with witness private key
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(witnessPrivateKey, prefixedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            erc1155Collection,
            address(0),
            1 ether,
            tokenHolder,
            1,
            100,
            signature,
            serialNumbers,
            1,
            timestamp
        );

        // Approve diamond to burn tokens
        IERC1155(erc1155Collection).setApprovalForAll(address(diamond), true);

        // Check initial unvault status
        assertFalse(
            EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(
                erc1155Collection, serialNumbers[0]
            )
        );

        // Unvault token
        EmblemVaultUnvaultFacet(address(diamond)).unvault(erc1155Collection, 1);
        vm.stopPrank();

        // Verify unvault status and unvaulter
        assertTrue(
            EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(
                erc1155Collection, serialNumbers[0]
            )
        );
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(
                erc1155Collection, serialNumbers[0]
            ),
            tokenHolder
        );
    }

    function testUnvaultWithSignedPriceWhenDisabled() public {
        // Disable unvaulting
        vm.startPrank(owner);
        EmblemVaultUnvaultFacet(address(diamond)).setUnvaultingEnabled(false);
        vm.stopPrank();

        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Approve and transfer to diamond
        ERC721VaultImplementation(nftCollection).approve(address(diamond), 2);
        ERC721VaultImplementation(nftCollection).transferFrom(tokenHolder, address(diamond), 2);
        vm.stopPrank();

        // Create unvault signature
        bytes memory unvaultSignature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            user1,
            2,
            3,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Should revert when trying to unvault with signed price
        vm.startPrank(user1);
        vm.expectRevert(LibEmblemVaultStorage.UnvaultingDisabled.selector);
        // Use timestamp 0 for signature verification in tests
        uint256 unvaultTimestamp = 0;
        EmblemVaultUnvaultFacet(address(diamond)).unvaultWithSignedPrice{value: 1 ether}(
            nftCollection, 2, 3, address(0), 1 ether, unvaultSignature, unvaultTimestamp
        );
        vm.stopPrank();
    }

    function testUnvaultWithLockedVault() public {
        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 2 ether); // Add extra ETH
        vm.startPrank(tokenHolder);
        // Use current timestamp for signature verification
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection, address(0), 1 ether, tokenHolder, 2, 2, signature, new uint256[](0), 1, 0
        );

        // Approve diamond
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);
        vm.stopPrank();

        //deal eth to owner
        vm.deal(owner, 1 ether);

        // Lock the vault
        vm.startPrank(owner);
        EmblemVaultCoreFacet(address(diamond)).lockVault(nftCollection, 2);
        vm.stopPrank();

        // Create unvault signature with lock acknowledgement
        bytes memory unvaultSignature = createSignatureWithLock(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            3,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Verify balances before unvault
        uint256 userBalanceBefore = tokenHolder.balance;

        // Unvault with signed price
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 unvaultTimestamp = 0;
        EmblemVaultUnvaultFacet(address(diamond)).unvaultWithSignedPrice{value: 1 ether}(
            nftCollection, 2, 3, address(0), 1 ether, unvaultSignature, unvaultTimestamp
        );

        // Verify balances after unvault
        uint256 userBalanceAfter = tokenHolder.balance;

        assertEq(userBalanceAfter, userBalanceBefore - 1 ether, "User balance incorrect");
        vm.stopPrank();

        // Verify unvault status
        assertTrue(EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(nftCollection, 2));
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(nftCollection, 2),
            tokenHolder
        );
    }

    function testPreventDirectBurn() public {
        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 timestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            timestamp
        );

        // Try to burn directly from user - should fail
        vm.expectRevert(abi.encodeWithSignature("NotDiamond()"));
        ERC721VaultImplementation(nftCollection).burn(2);
        vm.stopPrank();

        // Diamond can burn directly - this is allowed
        vm.prank(address(diamond));
        ERC721VaultImplementation(nftCollection).burn(2);

        // Verify token was burned
        vm.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        ERC721VaultImplementation(nftCollection).ownerOf(2);
    }

    function testBurnAddressWithUnvault() public {
        address burnAddr = address(0x123);

        // Add burn address
        vm.startPrank(owner);
        EmblemVaultUnvaultFacet(address(diamond)).setBurnAddress(burnAddr, true);
        vm.stopPrank();

        // Create signature for minting
        bytes memory signature = createSignature(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            1,
            witnessPrivateKey,
            new uint256[](0),
            0 // timestamp
        );

        // Mint token through diamond
        vm.deal(tokenHolder, 1 ether);
        vm.startPrank(tokenHolder);
        // Use timestamp 0 for signature verification in tests
        uint256 mintTimestamp = 0;
        EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
            nftCollection,
            address(0),
            1 ether,
            tokenHolder,
            2,
            2,
            signature,
            new uint256[](0),
            1,
            mintTimestamp
        );

        // Approve diamond
        ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

        // Unvault
        EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, 2);
        vm.stopPrank();

        // Verify unvault status
        assertTrue(EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(nftCollection, 2));
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(nftCollection, 2),
            tokenHolder
        );
    }

    function testUnvaultHistory() public {
        // Create multiple tokens and unvault them
        for (uint256 i = 2; i <= 4; i++) {
            // Create signature for minting
            bytes memory signature = createSignature(
                nftCollection,
                address(0),
                1 ether,
                tokenHolder,
                i,
                i,
                1,
                witnessPrivateKey,
                new uint256[](0),
                0 // timestamp
            );

            // Mint token through diamond
            vm.deal(tokenHolder, 1 ether);
            vm.startPrank(tokenHolder);
            // Use timestamp 0 for signature verification in tests
            uint256 timestamp = 0;
            EmblemVaultMintFacet(address(diamond)).buyWithSignedPrice{value: 1 ether}(
                nftCollection,
                address(0),
                1 ether,
                tokenHolder,
                i,
                i,
                signature,
                new uint256[](0),
                1,
                timestamp
            );

            // Approve diamond
            ERC721VaultImplementation(nftCollection).setApprovalForAll(address(diamond), true);

            // Unvault token
            EmblemVaultUnvaultFacet(address(diamond)).unvault(nftCollection, i);
            vm.stopPrank();
        }

        // Verify total unvaults
        assertEq(
            EmblemVaultUnvaultFacet(address(diamond)).getCollectionUnvaultCount(nftCollection), 3
        );

        // Verify each unvault individually
        for (uint256 i = 2; i <= 4; i++) {
            assertTrue(EmblemVaultUnvaultFacet(address(diamond)).isTokenUnvaulted(nftCollection, i));
            assertEq(
                EmblemVaultUnvaultFacet(address(diamond)).getTokenUnvaulter(nftCollection, i),
                tokenHolder
            );
        }
    }
}
