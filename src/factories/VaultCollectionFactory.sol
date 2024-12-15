// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../beacon/VaultBeacon.sol";
import "../beacon/VaultProxy.sol";
import "../interfaces/IVaultBeacon.sol";
import "../interfaces/IVaultProxy.sol";
import "../interfaces/IVaultCollectionFactory.sol";
import "../libraries/LibCollectionTypes.sol";
import "../libraries/LibErrors.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title VaultCollectionFactory
 * @notice Factory contract for deploying vault collection contracts using the beacon pattern
 * @dev Creates ERC721 and ERC1155 collection contracts that can mint individual vaults as tokens.
 *      Each collection is a token contract that can mint multiple vault tokens, making it a
 *      parent container for individual vaults. The factory manages these collection contracts
 *      through the beacon proxy pattern for upgradeability.
 */
contract VaultCollectionFactory is IVaultCollectionFactory {
    using LibCollectionTypes for uint8;

    // State variables
    address public immutable owner;
    address public erc721Beacon;
    address public erc1155Beacon;

    /**
     * @notice Constructor
     * @param _erc721Beacon Address of the ERC721 collection beacon
     * @param _erc1155Beacon Address of the ERC1155 collection beacon
     */
    constructor(address _erc721Beacon, address _erc1155Beacon) {
        LibErrors.revertIfZeroAddress(_erc721Beacon);
        LibErrors.revertIfZeroAddress(_erc1155Beacon);
        owner = msg.sender;
        erc721Beacon = _erc721Beacon;
        erc1155Beacon = _erc1155Beacon;
    }

    /**
     * @notice Create a new ERC721 vault collection contract
     * @param name The name of the collection
     * @param symbol The symbol of the collection
     * @return collection The address of the new collection contract that can mint individual vaults
     */
    function createERC721Collection(string memory name, string memory symbol)
        external
        returns (address collection)
    {
        // Deploy proxy
        collection = address(new ERC721VaultProxy(erc721Beacon));

        // Initialize collection contract
        try IERC721VaultProxy(collection).initialize(name, symbol) {
            emit ERC721CollectionCreated(collection, name, symbol);
        } catch {
            revert LibErrors.InitializationFailed();
        }
    }

    /**
     * @notice Create a new ERC1155 vault collection contract
     * @param uri The base URI for the collection's metadata
     * @return collection The address of the new collection contract that can mint individual vaults
     */
    function createERC1155Collection(string memory uri) external returns (address collection) {
        // Deploy proxy
        collection = address(new ERC1155VaultProxy(erc1155Beacon));

        // Initialize collection contract
        try IERC1155VaultProxy(collection).initialize(uri) {
            emit ERC1155CollectionCreated(collection, uri);
        } catch {
            revert LibErrors.InitializationFailed();
        }
    }

    /**
     * @notice Transfer ownership of a collection to a new owner
     * @param collection The collection address
     * @param newOwner The new owner address
     */
    function transferCollectionOwnership(address collection, address newOwner) external {
        if (msg.sender != owner) revert LibErrors.Unauthorized(msg.sender);
        if (!isCollection(collection)) revert LibErrors.InvalidCollection(collection);
        LibErrors.revertIfZeroAddress(newOwner);

        // Transfer ownership
        try OwnableUpgradeable(collection).transferOwnership(newOwner) {
            emit CollectionOwnershipTransferred(collection, newOwner);
        } catch {
            revert LibErrors.TransferFailed();
        }
    }

    /**
     * @notice Update the beacon for a collection type
     * @param collectionType The type of collection (1 for ERC721, 2 for ERC1155)
     * @param newBeacon The address of the new beacon
     */
    function updateBeacon(uint8 collectionType, address newBeacon) external {
        if (msg.sender != owner) revert LibErrors.Unauthorized(msg.sender);
        LibErrors.revertIfZeroAddress(newBeacon);

        if (!collectionType.isValidCollectionType()) {
            revert LibErrors.InvalidCollectionType(collectionType);
        }

        address oldBeacon;
        if (collectionType.isERC721Type()) {
            oldBeacon = erc721Beacon;
            erc721Beacon = newBeacon;
        } else {
            oldBeacon = erc1155Beacon;
            erc1155Beacon = newBeacon;
        }

        emit BeaconUpdated(collectionType, oldBeacon, newBeacon);
    }

    /**
     * @notice Get the beacon address for a collection type
     * @param collectionType The type of collection (1 for ERC721, 2 for ERC1155)
     * @return The beacon address
     */
    function getBeacon(uint8 collectionType) external view returns (address) {
        if (!collectionType.isValidCollectionType()) {
            revert LibErrors.InvalidCollectionType(collectionType);
        }

        return collectionType.isERC721Type() ? erc721Beacon : erc1155Beacon;
    }

    /**
     * @notice Get the implementation address for a collection type
     * @param collectionType The type of collection (1 for ERC721, 2 for ERC1155)
     * @return The implementation address
     */
    function getImplementation(uint8 collectionType) external view returns (address) {
        if (!collectionType.isValidCollectionType()) {
            revert LibErrors.InvalidCollectionType(collectionType);
        }

        address beacon = collectionType.isERC721Type() ? erc721Beacon : erc1155Beacon;
        return IVaultBeacon(beacon).implementation();
    }

    /**
     * @notice Get the type of a collection
     * @param collection The collection address
     * @return The collection type (1 for ERC721, 2 for ERC1155)
     */
    function getCollectionType(address collection) external view returns (uint8) {
        if (!isCollection(collection)) revert LibErrors.InvalidCollection(collection);

        address beaconAddress = IVaultProxy(collection).beacon();
        if (beaconAddress == erc721Beacon) {
            return LibCollectionTypes.ERC721_TYPE;
        } else {
            return LibCollectionTypes.ERC1155_TYPE;
        }
    }

    /**
     * @notice Check if an address is a vault collection contract created by this factory
     * @param collection The address to check
     * @return bool True if the address is a vault collection contract
     */
    function isCollection(address collection) public view returns (bool) {
        if (collection.code.length == 0) return false;

        try IVaultProxy(collection).beacon() returns (address beaconAddress) {
            return beaconAddress == erc721Beacon || beaconAddress == erc1155Beacon;
        } catch {
            return false;
        }
    }
}
