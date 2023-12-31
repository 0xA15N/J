// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "fns/registry/IFNS.sol";
import "./IBaseRegistrar.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBaseRegistrar is IERC721 {
    event NewNoNameCollisions(address indexed noNameCollisions);
    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event ResolverSet(address indexed resolver);
    event NameRegistered(string indexed name, uint256 indexed id, address indexed owner, uint256 expires);
    event NameRenewed(uint256 indexed id, uint256 expires);

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external;

    // Revoke controller permission for an address.
    function removeController(address controller) external;

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external;

    // Returns the expiration timestamp of the specified label hash.
    function nameExpires(uint256 id) external view returns (uint256);

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) external view returns (bool);

    // Returns true iff the specified name is not a collision in another registry
    function isNotCollision(string calldata name) external view returns (bool);

    /**
     * @dev Register a name.
     */
    function register(string calldata label, address owner, uint256 duration) external returns (uint256);

    function renew(uint256 id, uint256 duration) external returns (uint256);

    /**
     * @dev Reclaim ownership of a name in IFNS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external;
}
