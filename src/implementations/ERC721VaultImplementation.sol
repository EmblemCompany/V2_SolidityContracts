// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import "ERC721A-Upgradeable/extensions/ERC721ABurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../interfaces/IVaultProxy.sol";
import "../interfaces/IERC721AVault.sol";

/**
 * @title  ERC721VaultImplementation
 * @notice An upgradeable ERC721A-based contract with internal ↔ external token ID mapping.
 *         Designed to be owned and controlled by a "diamond" (via the `onlyDiamond` modifier).
 * @dev    Uses custom errors for more efficient reverts. Implements batch minting/burning.
 */
contract ERC721VaultImplementation is
    Initializable,
    ERC721AUpgradeable,
    ERC721ABurnableUpgradeable,
    OwnableUpgradeable,
    IVaultProxy,
    IERC721AVault
{
    using ERC721AStorage for ERC721AStorage.Layout;

    // --------------------------------------------------------
    // CUSTOM ERRORS
    // --------------------------------------------------------
    /// @notice Thrown if caller is not the diamond address.
    error NotDiamond();

    /// @notice Thrown if attempting to mint with an already mapped external ID.
    error ExternalIdAlreadyMinted();

    /// @notice Thrown if a requested token mapping does not exist.
    error TokenMappingNotFound();

    /// @notice Thrown if a requested token does not exist (or has been burned).
    error TokenDoesNotExist();

    /// @notice Thrown if the caller is neither the token owner nor approved to operate it.
    error NotTokenOwnerOrApproved();

    /// @notice Thrown when an input array is empty but expected to contain elements.
    error EmptyArrays();

    // --------------------------------------------------------
    // STORAGE
    // --------------------------------------------------------
    bytes32 private constant BEACON_SLOT =
        0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    string private constant DEFAULT_BASE_URI = "https://v2.emblemvault.io/meta/";
    uint256 private constant STARTING_TOKEN_ID = 1;

    /// @notice Maps an ERC721A internal token ID to its external token ID.
    mapping(uint256 => uint256) internal _externalTokenIdMap;

    /// @notice Maps an external token ID to its ERC721A internal token ID.
    mapping(uint256 => uint256) internal _reverseTokenIdMap;

    /// @notice The base URI for token metadata.
    string private _baseTokenURI;

    /// @notice The diamond contract address (must pass the `onlyDiamond` modifier to operate).
    address private _diamondAddress;

    // --------------------------------------------------------
    // EVENTS
    // --------------------------------------------------------
    /**
     * @notice Emitted when a token is minted.
     * @param to The address receiving the token.
     * @param internalTokenId The ERC721A internal token ID.
     * @param externalTokenId The associated external token ID.
     * @param data Additional data (if any).
     */
    event TokenMinted(
        address indexed to,
        uint256 indexed internalTokenId,
        uint256 indexed externalTokenId,
        bytes data
    );

    /**
     * @notice Emitted when a token is burned.
     * @param from The address that owned/initiated the burn.
     * @param internalTokenId The ERC721A internal token ID being burned.
     * @param externalTokenId The associated external token ID that is removed from mapping.
     * @param data Additional data (if any).
     */
    event TokenBurned(
        address indexed from,
        uint256 indexed internalTokenId,
        uint256 indexed externalTokenId,
        bytes data
    );

    /**
     * @notice Emitted when the base token URI is updated.
     * @param newBaseURI The new base URI string.
     */
    event BaseURIUpdated(string newBaseURI);

    /**
     * @notice Emitted when the token name or symbol is updated.
     * @param name The updated token name.
     * @param symbol The updated token symbol.
     */
    event DetailsUpdated(string name, string symbol);

    /**
     * @notice Disables initializers on deployment to prevent misuse.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Ensures only the diamond contract can call the function.
     */
    modifier onlyDiamond() {
        if (msg.sender != _diamondAddress) {
            revert NotDiamond();
        }
        _;
    }

    // --------------------------------------------------------
    // INITIALIZER
    // --------------------------------------------------------

    /**
     * @notice Initializes the upgradable ERC721A contract.
     * @dev    Calls various initializers for ERC721A, burnable, and ownership.
     *         Must only be called once. Caller is set as owner.
     * @param name_ The name of the ERC721 token.
     * @param symbol_ The symbol of the ERC721 token.
     * @param diamondAddress The address of the diamond controlling this vault.
     */
    function initialize(string calldata name_, string calldata symbol_, address diamondAddress)
        public
        initializerERC721A
        initializer
    {
        __ERC721A_init(name_, symbol_);
        __ERC721ABurnable_init();
        __Ownable_init(msg.sender);
        _baseTokenURI = DEFAULT_BASE_URI;
        _diamondAddress = diamondAddress;
    }

    // --------------------------------------------------------
    // MINTING
    // --------------------------------------------------------

    /**
     * @notice Mints a single token to a specified address with a given external ID.
     * @dev    Uses ERC721A `_mint()` to issue exactly 1 token.
     * @param to The address that will receive the newly minted token.
     * @param externalTokenId The external token ID to map against the new internal ID.
     *
     * Reverts:
     * - `ExternalIdAlreadyMinted()` if the external ID has already been used.
     */
    function mint(address to, uint256 externalTokenId) external override onlyDiamond {
        require(_reverseTokenIdMap[externalTokenId] == 0, ExternalIdAlreadyMinted());

        uint256 startTokenId = _nextTokenId();
        _mint(to, 1);

        _externalTokenIdMap[startTokenId] = externalTokenId;
        _reverseTokenIdMap[externalTokenId] = startTokenId;

        emit TokenMinted(to, startTokenId, externalTokenId, "");
    }

    /**
     * @notice Mints a single token to a specified address with a given external ID and additional data.
     * @dev    Similar to `mint()` but includes extra data in the `TokenMinted` event.
     * @param to The address that will receive the newly minted token.
     * @param externalTokenId The external token ID to map against the new internal ID.
     * @param data Arbitrary data to include in the minting event.
     *
     * Reverts:
     * - `ExternalIdAlreadyMinted()` if the external ID has already been used.
     */
    function mintWithData(address to, uint256 externalTokenId, bytes calldata data)
        external
        override
        onlyDiamond
    {
        require(_reverseTokenIdMap[externalTokenId] == 0, ExternalIdAlreadyMinted());

        uint256 startTokenId = _nextTokenId();
        _mint(to, 1);

        _externalTokenIdMap[startTokenId] = externalTokenId;
        _reverseTokenIdMap[externalTokenId] = startTokenId;

        emit TokenMinted(to, startTokenId, externalTokenId, data);
    }

    /**
     * @notice Batch-mints multiple tokens to a specified address.
     * @dev    Calls internal `_mintBatch(...)` with an empty `data` parameter.
     * @param to The address to receive the newly minted tokens.
     * @param externalTokenIds An array of external token IDs (one for each token).
     *
     * Reverts:
     * - `EmptyArrays()` if no IDs are provided.
     * - `ExternalIdAlreadyMinted()` if any external ID has already been used.
     */
    function batchMint(address to, uint256[] calldata externalTokenIds) external onlyDiamond {
        _mintBatch(to, externalTokenIds, "");
    }

    /**
     * @notice Batch-mints multiple tokens to a specified address with additional data.
     * @dev    Calls internal `_mintBatch(...)` with a `data` parameter for the `TokenMinted` event.
     * @param to The address to receive the newly minted tokens.
     * @param externalTokenIds An array of external token IDs (one for each token).
     * @param data Arbitrary data to be included in the `TokenMinted` event for each token.
     *
     * Reverts:
     * - `EmptyArrays()` if no IDs are provided.
     * - `ExternalIdAlreadyMinted()` if any external ID has already been used.
     */
    function batchMintWithData(address to, uint256[] calldata externalTokenIds, bytes calldata data)
        external
        onlyDiamond
    {
        _mintBatch(to, externalTokenIds, data);
    }

    /**
     * @notice Internal function to batch-mint tokens.
     * @dev    Mints `length` tokens at once, starting from `_nextTokenId()`.
     * @param to The address to receive the newly minted tokens.
     * @param externalTokenIds An array of external token IDs (one for each token).
     * @param data Arbitrary data to be included in the `TokenMinted` event for each token.
     *
     * Reverts:
     * - `EmptyArrays()` if the input array is empty.
     * - `ExternalIdAlreadyMinted()` if any external ID has already been used.
     */
    function _mintBatch(address to, uint256[] memory externalTokenIds, bytes memory data)
        internal
    {
        uint256 length = externalTokenIds.length;
        require(length > 0, EmptyArrays());

        for (uint256 i = 0; i < length;) {
            require(_reverseTokenIdMap[externalTokenIds[i]] == 0, ExternalIdAlreadyMinted());
            unchecked {
                ++i;
            }
        }

        uint256 startTokenId = _nextTokenId();
        _mint(to, length);

        for (uint256 i = 0; i < length;) {
            uint256 internalTokenId = startTokenId + i;
            uint256 externalTokenId = externalTokenIds[i];

            _externalTokenIdMap[internalTokenId] = externalTokenId;
            _reverseTokenIdMap[externalTokenId] = internalTokenId;

            emit TokenMinted(to, internalTokenId, externalTokenId, data);
            unchecked {
                ++i;
            }
        }
    }

    // --------------------------------------------------------
    // BURNING
    // --------------------------------------------------------

    /**
     * @notice Burns a single token, removing its external ID mapping.
     * @dev Only callable through the diamond proxy during unvault process
     * @param internalTokenId The internal token ID of the token to burn.
     */
    function burn(uint256 internalTokenId)
        public
        override(ERC721ABurnableUpgradeable, IERC721AVault)
        onlyDiamond
    {
        _burnSingle(internalTokenId, "");
    }

    /**
     * @notice Burns a single token, removing its external ID mapping, with extra data.
     * @dev Only callable through the diamond proxy during unvault process
     * @param internalTokenId The internal token ID of the token to burn.
     * @param data Arbitrary data to include in the `TokenBurned` event.
     */
    function burnWithData(uint256 internalTokenId, bytes calldata data)
        public
        override
        onlyDiamond
    {
        _burnSingle(internalTokenId, data);
    }

    /**
     * @notice Internal function to handle single-token burning and mapping cleanup.
     * @dev Only called through diamond proxy during unvault process
     * @param internalTokenId The internal token ID to burn.
     * @param data Data to include in the `TokenBurned` event.
     */
    function _burnSingle(uint256 internalTokenId, bytes memory data) internal {
        uint256 externalTokenId = _externalTokenIdMap[internalTokenId];
        delete _reverseTokenIdMap[externalTokenId];
        delete _externalTokenIdMap[internalTokenId];

        // Use _burn instead of super.burn to bypass approval checks
        // The onlyDiamond modifier provides sufficient authorization
        _burn(internalTokenId);

        emit TokenBurned(_msgSender(), internalTokenId, externalTokenId, data);
    }

    /**
     * @notice Batch-burns multiple tokens, removing their external ID mappings.
     * @dev Only callable through the diamond proxy during unvault process
     * @param internalTokenIds An array of internal token IDs to burn.
     */
    function batchBurn(uint256[] calldata internalTokenIds) external override onlyDiamond {
        _burnBatch(internalTokenIds, "");
    }

    /**
     * @notice Batch-burns multiple tokens, removing their external ID mappings, with extra data.
     * @dev Only callable through the diamond proxy during unvault process
     * @param internalTokenIds An array of internal token IDs to burn.
     * @param data Arbitrary data to include in each `TokenBurned` event.
     */
    function batchBurnWithData(uint256[] calldata internalTokenIds, bytes calldata data)
        external
        override
        onlyDiamond
    {
        _burnBatch(internalTokenIds, data);
    }

    /**
     * @notice Internal function to handle batch burning logic.
     * @dev Only called through diamond proxy during unvault process
     * @param internalTokenIds An array of internal token IDs to burn.
     * @param data Data to include in the `TokenBurned` event for each burned token.
     *
     * Reverts:
     * - `EmptyArrays()` if the array is empty.
     */
    function _burnBatch(uint256[] memory internalTokenIds, bytes memory data) internal {
        uint256 length = internalTokenIds.length;
        require(length > 0, EmptyArrays());

        for (uint256 i = 0; i < length;) {
            _burnSingle(internalTokenIds[i], data);
            unchecked {
                ++i;
            }
        }
    }

    // --------------------------------------------------------
    // GETTERS
    // --------------------------------------------------------

    /**
     * @notice Retrieves the internal token ID associated with a given external token ID.
     * @param externalTokenId The external token ID to look up.
     * @return The internal token ID mapped to `externalTokenId`.
     *
     * Reverts:
     * - `TokenMappingNotFound()` if no mapping exists.
     * - `TokenDoesNotExist()` if the resulting internal token has been burned or never existed.
     */
    function getInternalTokenId(uint256 externalTokenId) external view override returns (uint256) {
        uint256 internalId = _reverseTokenIdMap[externalTokenId];
        require(internalId != 0, TokenMappingNotFound());
        require(_exists(internalId), TokenDoesNotExist());
        return internalId;
    }

    /**
     * @notice Retrieves the external token ID associated with a given internal token ID.
     * @param internalTokenId The internal token ID to look up.
     * @return The external token ID mapped to `internalTokenId`.
     *
     * Reverts:
     * - `TokenDoesNotExist()` if the token has been burned or never existed.
     * - `TokenMappingNotFound()` if no external ID is mapped.
     */
    function getExternalTokenId(uint256 internalTokenId) external view override returns (uint256) {
        require(_exists(internalTokenId), TokenDoesNotExist());
        uint256 externalId = _externalTokenIdMap[internalTokenId];
        require(externalId != 0, TokenMappingNotFound());
        return externalId;
    }

    /**
     * @dev Returns the base URI for computing `tokenURI`.
     * Overridden from ERC721A.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    // --------------------------------------------------------
    // SETTERS
    // --------------------------------------------------------

    /**
     * @notice Updates the base URI for token metadata.
     * @dev    Only callable by the diamond contract.
     * @param baseURI The new base URI to set.
     */
    function setBaseURI(string calldata baseURI) external override onlyDiamond {
        _baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    /**
     * @notice Updates the token name and symbol stored in ERC721AStorage.
     * @dev    Only callable by the diamond contract.
     * @param name_ The new token name.
     * @param symbol_ The new token symbol.
     */
    function setDetails(string calldata name_, string calldata symbol_)
        external
        override
        onlyDiamond
    {
        ERC721AStorage.Layout storage layout = ERC721AStorage.layout();
        layout._name = name_;
        layout._symbol = symbol_;
        emit DetailsUpdated(name_, symbol_);
    }

    // --------------------------------------------------------
    // INTERFACE & PROXY-RELATED
    // --------------------------------------------------------

    /**
     * @notice Checks if this contract implements a given interface ID.
     * @dev    Combines ERC721A, ERC165, and custom interfaces (IVaultProxy, IERC721AVault).
     * @param _interfaceId The interface ID to check.
     * @return True if the contract implements the given interface ID, false otherwise.
     */
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC721AUpgradeable, IERC165, IERC721AUpgradeable)
        returns (bool)
    {
        return _interfaceId == type(IVaultProxy).interfaceId
            || _interfaceId == type(IERC721AVault).interfaceId || _interfaceId == 0xf4a95f26 // ERC721A
            || super.supportsInterface(_interfaceId);
    }

    /**
     * @notice Returns the version string of this implementation.
     * @return A string representing the version, e.g. "1".
     */
    function version() external pure override returns (string memory) {
        return "1";
    }

    /**
     * @notice Returns the interface ID of the vault proxy.
     * @return The bytes4 interface ID.
     */
    function interfaceId() external pure override returns (bytes4) {
        return type(IVaultProxy).interfaceId;
    }

    /**
     * @notice Retrieves the beacon address from the defined `BEACON_SLOT` via inline assembly.
     * @return beaconAddress The address stored in `BEACON_SLOT`.
     */
    function beacon()
        external
        view
        override(IERC721AVault, IVaultProxy)
        returns (address beaconAddress)
    {
        assembly {
            beaconAddress := sload(BEACON_SLOT)
        }
    }

    /**
     * @notice Returns the current implementation address (i.e., this contract).
     * @return The address of this contract.
     */
    function implementation()
        external
        view
        override(IERC721AVault, IVaultProxy)
        returns (address)
    {
        return address(this);
    }

    /**
     * @dev Overridden from ERC721A to define the starting token ID as `1`.
     * @return The token ID to start minting from.
     */
    function _startTokenId() internal pure override returns (uint256) {
        return STARTING_TOKEN_ID;
    }
}
