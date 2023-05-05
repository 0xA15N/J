// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITextResolver {
    event TextChanged(bytes32 indexed node, string indexed indexedKey, string key, string value);

    /**
     * Returns the text data associated with an FNS node and key.
     * @param node The FNS node to query.
     * @param key The text data key to query.
     * @return The associated text data.
     */
    function text(bytes32 node, string calldata key) external view returns (string memory);
}
