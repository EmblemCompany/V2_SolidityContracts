// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC165.sol";

interface IERC1155 is IERC165 {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);

    function balanceOf(address account, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
    function mint(address to, uint256 id, uint256 amount) external;
    function mintWithSerial(
        address to,
        uint256 id,
        uint256 amount,
        uint256[] calldata serialNumbers
    ) external;
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256[][] calldata serialNumbers
    ) external;
    function burn(address account, uint256 id, uint256 value) external;
    function burnBatch(address account, uint256[] calldata ids, uint256[] calldata values)
        external;
}
