//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {ERC1155Fuse, IERC165, IERC1155MetadataURI} from "./ERC1155Fuse.sol";
import {Controllable} from "fns/root/Controllable.sol";
import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, PARENT_CANNOT_CONTROL, CAN_DO_EVERYTHING, IS_DOT_ETH, CAN_EXTEND_EXPIRY, PARENT_CONTROLLED_FUSES, USER_SETTABLE_FUSES} from "./INameWrapper.sol";
import {INameWrapperUpgrade} from "./INameWrapperUpgrade.sol";
import {IMetadataService} from "./IMetadataService.sol";
import {IFNS} from "fns/registry/IFNS.sol";
import {IBaseRegistrar} from "fns/flr-registrar/IBaseRegistrar.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BytesUtils} from "./BytesUtils.sol";
import {ERC20Recoverable} from "fns/utils/ERC20Recoverable.sol";
import {IMintedDomainNames} from "fns/flr-registrar/IMintedDomainNames.sol";

error UnauthorisedAddr(bytes32 node, address addr);
error IncompatibleParent();
error IncorrectTokenType();
error LabelMismatch(bytes32 labelHash, bytes32 expectedLabelhash);
error LabelTooShort();
error LabelTooLong(string label);
error IncorrectTargetOwner(address owner);
error CannotUpgrade();
error OperationProhibited(bytes32 node);
error NameIsNotWrapped();
error NameIsStillExpired();

contract NameWrapper is
    Ownable,
    ERC1155Fuse,
    INameWrapper,
    Controllable,
    IERC721Receiver,
    ERC20Recoverable
{
    using BytesUtils for bytes;

    IFNS public immutable fns;
    IBaseRegistrar public immutable registrar;
    IMetadataService public metadataService;
    mapping(bytes32 => bytes) public names;
    string public constant name = "NameWrapper";

    uint64 private constant GRACE_PERIOD = 90 days;
    bytes32 private constant FLR_NODE =
        0xfd9ed02f44147ba87d942b154c98562d831e3a24daea862ee12868ac20f7bcc3;
    // Labelhash is just the keccak of "flr", sometimes represented as a uint256
    bytes32 private constant FLR_LABELHASH = 0x848313180a0fba6baf0d056afcae526bd33cc52dc58a1a864e1906017cb3ceaf;
    bytes32 private constant ROOT_NODE =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    INameWrapperUpgrade public upgradeContract;
    IMintedDomainNames public mintedDomainNamesContract;

    uint64 private constant MAX_EXPIRY = type(uint64).max;

    constructor(
        IFNS _ens,
        IBaseRegistrar _registrar,
        IMetadataService _metadataService
    ) {
        fns = _ens;
        registrar = _registrar;
        metadataService = _metadataService;

        /* Burn PARENT_CANNOT_CONTROL and CANNOT_UNWRAP fuses for ROOT_NODE and FLR_NODE */

        _setData(
            uint256(FLR_NODE),
            address(0),
            uint32(PARENT_CANNOT_CONTROL | CANNOT_UNWRAP),
            MAX_EXPIRY
        );
        _setData(
            uint256(ROOT_NODE),
            address(0),
            uint32(PARENT_CANNOT_CONTROL | CANNOT_UNWRAP),
            MAX_EXPIRY
        );
        names[ROOT_NODE] = "\x00";
        names[FLR_NODE] = "\x03flr\x00";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Fuse, INameWrapper) returns (bool) {
        return
            interfaceId == type(INameWrapper).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Allows the owner of the contract to update the MintedIds contract, in case it
     *      needs to be updated in the future
     * @dev This assumes that the interface remains constant
     * @param newContract the new MintedIds Contract address
     */
    function updateMintedDomainNamesContract(IMintedDomainNames newContract) public onlyOwner {
        mintedDomainNamesContract = newContract;
    }

    /* ERC1155 Fuse */

    /**
     * @notice Gets the owner of a name
     * @param id The tokenId associated with the namehash of the domain label
     * @return owner The owner of the name
     */
    function ownerOf(
        uint256 id
    ) public view override(ERC1155Fuse, INameWrapper) returns (address owner) {
        return super.ownerOf(id);
    }

    /**
     * @notice Gets the owner of a name
     * @param label Label as a string of the .flr domain to wrap. For "test.flr", input "test"
     * @return owner The owner of the name
     */
    function ownerOfLabel(string calldata label) public view returns (address owner) {
        return ownerOf(uint256(keccak256(abi.encodePacked(FLR_NODE, keccak256(bytes(label))))));
    }

    /**
     * @notice Gets the data for a name
     * @param id Namehash of the name
     * @return owner Owner of the name
     * @return fuses Fuses of the name
     * @return expiry Expiry of the name
     */

    function getData(
        uint256 id
    )
        public
        view
        override(ERC1155Fuse, INameWrapper)
        returns (address owner, uint32 fuses, uint64 expiry)
    {
        (owner, fuses, expiry) = super.getData(id);

        (owner, fuses) = _clearOwnerAndFuses(owner, fuses, expiry);
    }

    /* Metadata service */

    /**
     * @notice Set the metadata service. Only the owner can do this
     * @param _metadataService The new metadata service
     */

    function setMetadataService(
        IMetadataService _metadataService
    ) public onlyOwner {
        metadataService = _metadataService;
    }

    /**
     * @notice Get the metadata uri
     * @param tokenId The id of the token
     * @return string uri of the metadata service
     */

    function uri(
        uint256 tokenId
    )
        public
        view
        override(INameWrapper, IERC1155MetadataURI)
        returns (string memory)
    {
        return metadataService.uri(tokenId);
    }

    /**
     * @notice Set the address of the upgradeContract of the contract. only admin can do this
     * @dev The default value of upgradeContract is the 0 address. Use the 0 address at any time
     * to make the contract not upgradable.
     * @param _upgradeAddress address of an upgraded contract
     */

    function setUpgradeContract(
        INameWrapperUpgrade _upgradeAddress
    ) public onlyOwner {
        if (address(upgradeContract) != address(0)) {
            registrar.setApprovalForAll(address(upgradeContract), false);
            fns.setApprovalForAll(address(upgradeContract), false);
        }

        upgradeContract = _upgradeAddress;

        if (address(upgradeContract) != address(0)) {
            registrar.setApprovalForAll(address(upgradeContract), true);
            fns.setApprovalForAll(address(upgradeContract), true);
        }
    }

    /**
     * @notice Checks if msg.sender is the owner or approved by the owner of a name
     * @param node namehash of the name to check
     */

    modifier onlyTokenOwner(bytes32 node) {
        if (!canModifyName(node, msg.sender)) {
            revert UnauthorisedAddr(node, msg.sender);
        }

        _;
    }

    /**
     * @notice Checks if owner or approved by owner
     * @param node namehash of the name to check
     * @param addr which address to check permissions for
     * @return whether or not is owner or approved
     */

    function canModifyName(
        bytes32 node,
        address addr
    ) public view returns (bool) {
        (address owner, uint32 fuses, uint64 expiry) = getData(uint256(node));
        return
            (owner == addr || isApprovedForAll(owner, addr)) &&
            (fuses & IS_DOT_ETH == 0 ||
                expiry - GRACE_PERIOD >= block.timestamp);
    }

    /**
     * @notice Wraps a .flr domain, creating a new token and sending the original ERC721 token to this contract
     * @dev Can be called by the owner of the name on the .flr registrar or an authorised caller on the registrar
     * @param label Label as a string of the .flr domain to wrap
     * @param wrappedOwner Owner of the name in this contract
     * @param ownerControlledFuses Initial owner-controlled fuses to set
     * @param resolver Resolver contract address
     */

    function wrapETH2LD(
        string calldata label,
        address wrappedOwner,
        uint16 ownerControlledFuses,
        address resolver
    ) public {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        address registrant = registrar.ownerOf(tokenId);
        if (
            registrant != msg.sender &&
            !registrar.isApprovedForAll(registrant, msg.sender)
        ) {
            revert UnauthorisedAddr(
                _makeNode(FLR_NODE, bytes32(tokenId)),
                msg.sender
            );
        }

        // transfer the token from the user to this contract
        registrar.transferFrom(registrant, address(this), tokenId);

        // transfer the fns record back to the new owner (this contract)
        registrar.reclaim(tokenId, address(this));

        uint64 expiry = uint64(registrar.nameExpires(tokenId)) + GRACE_PERIOD;

        _wrapETH2LD(
            label,
            wrappedOwner,
            ownerControlledFuses,
            expiry,
            resolver
        );
    }

    /**
     * @dev Registers a new .flr second-level domain and wraps it.
     *      Only callable by authorised controllers.
     * @param label The label to register (Eg, 'foo' for 'foo.flr').
     * @param wrappedOwner The owner of the wrapped name.
     * @param duration The duration, in seconds, to register the name for.
     * @param resolver The resolver address to set on the IFNS registry (optional).
     * @param ownerControlledFuses Initial owner-controlled fuses to set
     * @return registrarExpiry The expiry date of the new name on the .flr registrar, in seconds since the Unix epoch.
     */

    function registerAndWrapETH2LD(
        string calldata label,
        address wrappedOwner,
        uint256 duration,
        address resolver,
        uint16 ownerControlledFuses
    ) external onlyController returns (uint256 registrarExpiry) {
        registrarExpiry = registrar.register(label, address(this), duration);
        _wrapETH2LD(
            label,
            wrappedOwner,
            ownerControlledFuses,
            uint64(registrarExpiry) + GRACE_PERIOD,
            resolver
        );
    }

    /**
     * @notice Renews a .flr second-level domain.
     * @dev Only callable by authorised controllers.
     * @param tokenId The hash of the label to register (eg, `keccak256('foo')`, for 'foo.flr').
     * @param duration The number of seconds to renew the name for.
     * @return expires The expiry date of the name on the .flr registrar, in seconds since the Unix epoch.
     */

    function renew(
        uint256 tokenId,
        uint256 duration
    ) external onlyController returns (uint256 expires) {
        bytes32 node = _makeNode(FLR_NODE, bytes32(tokenId));

        uint256 registrarExpiry = registrar.renew(tokenId, duration);

        // Do not set anything in wrapper if name is not wrapped
        try registrar.ownerOf(tokenId) returns (address registrarOwner) {
            if (
                registrarOwner != address(this) ||
                fns.owner(node) != address(this)
            ) {
                return registrarExpiry;
            }
        } catch {
            return registrarExpiry;
        }

        // set expiry in Wrapper
        uint64 expiry = uint64(registrarExpiry) + GRACE_PERIOD;

        //use super to allow names expired on the wrapper, but not expired on the registrar to renew()
        (address owner, uint32 fuses, ) = super.getData(uint256(node));
        _setData(node, owner, fuses, expiry);

        return registrarExpiry;
    }

    /**
     * @notice Wraps a non .flr domain, of any kind. Could be a DNSSEC name vitalik.xyz or a subdomain
     * @dev Can be called by the owner in the registry or an authorised caller in the registry
     * @param _name The name to wrap, in DNS format
     * @param wrappedOwner Owner of the name in this contract
     * @param resolver Resolver contract
     */

    function wrap(
        bytes calldata _name,
        address wrappedOwner,
        address resolver
    ) public {
        (bytes32 labelhash, uint256 offset) = _name.readLabel(0);
        bytes32 parentNode = _name.namehash(offset);
        bytes32 node = _makeNode(parentNode, labelhash);

        names[node] = _name;

        if (parentNode == FLR_NODE) {
            revert IncompatibleParent();
        }

        address owner = fns.owner(node);

        if (owner != msg.sender && !fns.isApprovedForAll(owner, msg.sender)) {
            revert UnauthorisedAddr(node, msg.sender);
        }

        if (resolver != address(0)) {
            fns.setResolver(node, resolver);
        }

        fns.setOwner(node, address(this));

        _wrap(node, _name, wrappedOwner, 0, 0);
    }

    /**
     * @notice Unwraps a .flr domain. e.g. vitalik.flr
     * @dev Can be called by the owner in the wrapper or an authorised caller in the wrapper
     * @param labelhash Labelhash of the .flr domain
     * @param registrant Sets the owner in the .flr registrar to this address
     * @param controller Sets the owner in the registry to this address
     */

    function unwrapETH2LD(
        bytes32 labelhash,
        address registrant,
        address controller
    ) public onlyTokenOwner(_makeNode(FLR_NODE, labelhash)) {
        if (registrant == address(this)) {
            revert IncorrectTargetOwner(registrant);
        }
        _unwrap(_makeNode(FLR_NODE, labelhash), controller);
        registrar.safeTransferFrom(
            address(this),
            registrant,
            uint256(labelhash)
        );
    }

    /**
     * @notice Unwraps a non .flr domain, of any kind. Could be a DNSSEC name vitalik.xyz or a subdomain
     * @dev Can be called by the owner in the wrapper or an authorised caller in the wrapper
     * @param parentNode Parent namehash of the name e.g. vitalik.xyz would be namehash('xyz')
     * @param labelhash Labelhash of the name, e.g. vitalik.xyz would be keccak256('vitalik')
     * @param controller Sets the owner in the registry to this address
     */

    function unwrap(
        bytes32 parentNode,
        bytes32 labelhash,
        address controller
    ) public onlyTokenOwner(_makeNode(parentNode, labelhash)) {
        if (parentNode == FLR_NODE) {
            revert IncompatibleParent();
        }
        if (controller == address(0x0) || controller == address(this)) {
            revert IncorrectTargetOwner(controller);
        }
        _unwrap(_makeNode(parentNode, labelhash), controller);
    }

    /**
     * @notice Sets fuses of a name
     * @param node Namehash of the name
     * @param ownerControlledFuses Owner-controlled fuses to burn
     * @return Old fuses
     */

    function setFuses(
        bytes32 node,
        uint16 ownerControlledFuses
    )
        public
        onlyTokenOwner(node)
        operationAllowed(node, CANNOT_BURN_FUSES)
        returns (uint32)
    {
        // owner protected by onlyTokenOwner
        (address owner, uint32 oldFuses, uint64 expiry) = getData(
            uint256(node)
        );
        _setFuses(node, owner, ownerControlledFuses | oldFuses, expiry, expiry);
        return oldFuses;
    }

    /**
     * @notice Extends expiry for a name
     * @param parentNode Parent namehash of the name e.g. vitalik.xyz would be namehash('xyz')
     * @param labelhash Labelhash of the name, e.g. vitalik.xyz would be keccak256('vitalik')
     * @param expiry When the name will expire in seconds since the Unix epoch
     * @return New expiry
     */

    function extendExpiry(
        bytes32 parentNode,
        bytes32 labelhash,
        uint64 expiry
    ) public returns (uint64) {
        bytes32 node = _makeNode(parentNode, labelhash);

        // this flag is used later, when checking fuses
        bool canModifyParentName = canModifyName(parentNode, msg.sender);
        // only allow the owner of the name or owner of the parent name
        if (!canModifyParentName && !canModifyName(node, msg.sender)) {
            revert UnauthorisedAddr(node, msg.sender);
        }

        (address owner, uint32 fuses, uint64 oldExpiry) = getData(
            uint256(node)
        );

        // Either CAN_EXTEND_EXPIRY must be set, or the caller must have permission to modify the parent name
        if (!canModifyParentName && fuses & CAN_EXTEND_EXPIRY == 0) {
            revert OperationProhibited(node);
        }

        // max expiry is set to the expiry of the parent
        (, , uint64 maxExpiry) = getData(uint256(parentNode));
        expiry = _normaliseExpiry(expiry, oldExpiry, maxExpiry);

        _setData(node, owner, fuses, expiry);
        emit ExpiryExtended(node, expiry);
        return expiry;
    }

    /**
     * @notice Upgrades a domain of any kind. Could be a .flr name vitalik.flr, a DNSSEC name vitalik.xyz, or a subdomain
     * @dev Can be called by the owner or an authorised caller
     * @param _name The name to upgrade, in DNS format
     * @param extraData Extra data to pass to the upgrade contract
     */

    function upgrade(bytes calldata _name, bytes calldata extraData) public {
        bytes32 node = _name.namehash(0);

        if (address(upgradeContract) == address(0)) {
            revert CannotUpgrade();
        }

        if (!canModifyName(node, msg.sender)) {
            revert UnauthorisedAddr(node, msg.sender);
        }

        (address currentOwner, uint32 fuses, uint64 expiry) = getData(
            uint256(node)
        );

        _burn(uint256(node));

        upgradeContract.wrapFromUpgrade(
            _name,
            currentOwner,
            fuses,
            expiry,
            extraData
        );
    }

    /** 
    /* @notice Sets fuses of a name that you own the parent of. Can also be called by the owner of a .flr name
     * @param parentNode Parent namehash of the name e.g. vitalik.xyz would be namehash('xyz')
     * @param labelhash Labelhash of the name, e.g. vitalik.xyz would be keccak256('vitalik')
     * @param fuses Fuses to burn
     * @param expiry When the name will expire in seconds since the Unix epoch
     */

    function setChildFuses(
        bytes32 parentNode,
        bytes32 labelhash,
        uint32 fuses,
        uint64 expiry
    ) public {
        bytes32 node = _makeNode(parentNode, labelhash);
        _checkFusesAreSettable(node, fuses);
        (address owner, uint32 oldFuses, uint64 oldExpiry) = getData(
            uint256(node)
        );
        if (owner == address(0) || fns.owner(node) != address(this)) {
            revert NameIsNotWrapped();
        }
        // max expiry is set to the expiry of the parent
        (, uint32 parentFuses, uint64 maxExpiry) = getData(uint256(parentNode));
        if (parentNode == ROOT_NODE) {
            if (!canModifyName(node, msg.sender)) {
                revert UnauthorisedAddr(node, msg.sender);
            }
        } else {
            if (!canModifyName(parentNode, msg.sender)) {
                revert UnauthorisedAddr(node, msg.sender);
            }
        }

        _checkParentFuses(node, fuses, parentFuses);

        expiry = _normaliseExpiry(expiry, oldExpiry, maxExpiry);

        // if PARENT_CANNOT_CONTROL has been burned and fuses have changed
        if (
            oldFuses & PARENT_CANNOT_CONTROL != 0 &&
            oldFuses | fuses != oldFuses
        ) {
            revert OperationProhibited(node);
        }
        fuses |= oldFuses;
        _setFuses(node, owner, fuses, oldExpiry, expiry);
    }

    /**
     * @notice Sets the subdomain owner in the registry and then wraps the subdomain
     * @param parentNode Parent namehash of the subdomain
     * @param label Label of the subdomain as a string
     * @param owner New owner in the wrapper
     * @param fuses Initial fuses for the wrapped subdomain
     * @param expiry When the name will expire in seconds since the Unix epoch
     * @return node Namehash of the subdomain
     */

    function setSubnodeOwner(
        bytes32 parentNode,
        string calldata label,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) public onlyTokenOwner(parentNode) returns (bytes32 node) {
        bytes32 labelhash = keccak256(bytes(label));
        node = _makeNode(parentNode, labelhash);
        _checkCanCallSetSubnodeOwner(parentNode, node);
        _checkFusesAreSettable(node, fuses);
        bytes memory _name = _saveLabel(parentNode, node, label);
        expiry = _checkParentFusesAndExpiry(parentNode, node, fuses, expiry);

        if (!_isWrapped(node)) {
            fns.setSubnodeOwner(parentNode, labelhash, address(this));
            _wrap(node, _name, owner, fuses, expiry);
        } else {
            _updateName(parentNode, node, label, owner, fuses, expiry);
        }
    }

    /**
     * @notice Sets the subdomain owner in the registry with records and then wraps the subdomain
     * @param parentNode parent namehash of the subdomain
     * @param label label of the subdomain as a string
     * @param owner new owner in the wrapper
     * @param resolver resolver contract in the registry
     * @param ttl ttl in the registry
     * @param fuses initial fuses for the wrapped subdomain
     * @param expiry When the name will expire in seconds since the Unix epoch
     * @return node Namehash of the subdomain
     */

    function setSubnodeRecord(
        bytes32 parentNode,
        string memory label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) public onlyTokenOwner(parentNode) returns (bytes32 node) {
        bytes32 labelhash = keccak256(bytes(label));
        node = _makeNode(parentNode, labelhash);
        _checkCanCallSetSubnodeOwner(parentNode, node);
        _checkFusesAreSettable(node, fuses);
        _saveLabel(parentNode, node, label);
        expiry = _checkParentFusesAndExpiry(parentNode, node, fuses, expiry);
        if (!_isWrapped(node)) {
            fns.setSubnodeRecord(
                parentNode,
                labelhash,
                address(this),
                resolver,
                ttl
            );
            _storeNameAndWrap(parentNode, node, label, owner, fuses, expiry);
        } else {
            fns.setSubnodeRecord(
                parentNode,
                labelhash,
                address(this),
                resolver,
                ttl
            );
            _updateName(parentNode, node, label, owner, fuses, expiry);
        }
    }

    /**
     * @notice Sets records for the name in the IFNS Registry
     * @param node Namehash of the name to set a record for
     * @param owner New owner in the registry
     * @param resolver Resolver contract
     * @param ttl Time to live in the registry
     */

    function setRecord(
        bytes32 node,
        address owner,
        address resolver,
        uint64 ttl
    )
        public
        onlyTokenOwner(node)
        operationAllowed(
            node,
            CANNOT_TRANSFER | CANNOT_SET_RESOLVER | CANNOT_SET_TTL
        )
    {
        fns.setRecord(node, address(this), resolver, ttl);
        if (owner == address(0)) {
            (, uint32 fuses, ) = getData(uint256(node));
            if (fuses & IS_DOT_ETH == IS_DOT_ETH) {
                revert IncorrectTargetOwner(owner);
            }
            _unwrap(node, address(0));
        } else {
            address oldOwner = ownerOf(uint256(node));
            _transfer(oldOwner, owner, uint256(node), 1, "");
        }
    }

    /**
     * @notice Sets resolver contract in the registry
     * @param node namehash of the name
     * @param resolver the resolver contract
     */

    function setResolver(
        bytes32 node,
        address resolver
    ) public onlyTokenOwner(node) operationAllowed(node, CANNOT_SET_RESOLVER) {
        fns.setResolver(node, resolver);
    }

    /**
     * @notice Sets TTL in the registry
     * @param node Namehash of the name
     * @param ttl TTL in the registry
     */

    function setTTL(
        bytes32 node,
        uint64 ttl
    ) public onlyTokenOwner(node) operationAllowed(node, CANNOT_SET_TTL) {
        fns.setTTL(node, ttl);
    }

    /**
     * @dev Allows an operation only if none of the specified fuses are burned.
     * @param node The namehash of the name to check fuses on.
     * @param fuseMask A bitmask of fuses that must not be burned.
     */

    modifier operationAllowed(bytes32 node, uint32 fuseMask) {
        (, uint32 fuses, ) = getData(uint256(node));
        if (fuses & fuseMask != 0) {
            revert OperationProhibited(node);
        }
        _;
    }

    /**
     * @notice Check whether a name can call setSubnodeOwner/setSubnodeRecord
     * @dev Checks both CANNOT_CREATE_SUBDOMAIN and PARENT_CANNOT_CONTROL and whether not they have been burnt
     *      and checks whether the owner of the subdomain is 0x0 for creating or already exists for
     *      replacing a subdomain. If either conditions are true, then it is possible to call
     *      setSubnodeOwner
     * @param parentNode Namehash of the parent name to check
     * @param subnode Namehash of the subname to check
     */

    function _checkCanCallSetSubnodeOwner(
        bytes32 parentNode,
        bytes32 subnode
    ) internal view {
        (
            address subnodeOwner,
            uint32 subnodeFuses,
            uint64 subnodeExpiry
        ) = getData(uint256(subnode));

        // check if the registry owner is 0 and expired
        // check if the wrapper owner is 0 and expired
        // If either, then check parent fuses for CANNOT_CREATE_SUBDOMAIN
        bool expired = subnodeExpiry < block.timestamp;
        if (
            expired &&
            // protects a name that has been unwrapped with PCC and doesn't allow the parent to take control by recreating it if unexpired
            (subnodeOwner == address(0) ||
                // protects a name that has been burnt and doesn't allow the parent to take control by recreating it if unexpired
                fns.owner(subnode) == address(0))
        ) {
            (, uint32 parentFuses, ) = getData(uint256(parentNode));
            if (parentFuses & CANNOT_CREATE_SUBDOMAIN != 0) {
                revert OperationProhibited(subnode);
            }
        } else {
            if (subnodeFuses & PARENT_CANNOT_CONTROL != 0) {
                revert OperationProhibited(subnode);
            }
        }
    }

    /**
     * @notice Checks all Fuses in the mask are burned for the node
     * @param node Namehash of the name
     * @param fuseMask The fuses you want to check
     * @return Boolean of whether or not all the selected fuses are burned
     */

    function allFusesBurned(
        bytes32 node,
        uint32 fuseMask
    ) public view returns (bool) {
        (, uint32 fuses, ) = getData(uint256(node));
        return fuses & fuseMask == fuseMask;
    }

    /**
     * @notice Checks if a name is wrapped
     * @param node Namehash of the name
     * @return Boolean of whether or not the name is wrapped
     */

    function isWrapped(bytes32 node) public view returns (bool) {
        bytes memory _name = names[node];
        if (_name.length == 0) {
            return false;
        }
        (bytes32 labelhash, uint256 offset) = _name.readLabel(0);
        bytes32 parentNode = _name.namehash(offset);
        return isWrapped(parentNode, labelhash);
    }

    /**
     * @notice Checks if a name is wrapped in a more gas efficient way
     * @param parentNode Namehash of the name
     * @param labelhash Namehash of the name
     * @return Boolean of whether or not the name is wrapped
     */

    function isWrapped(
        bytes32 parentNode,
        bytes32 labelhash
    ) public view returns (bool) {
        bytes32 node = _makeNode(parentNode, labelhash);
        bool wrapped = _isWrapped(node);
        if (parentNode != FLR_NODE) {
            return wrapped;
        }
        try registrar.ownerOf(uint256(labelhash)) returns (address owner) {
            return owner == address(this);
        } catch {
            return false;
        }
    }

    function onERC721Received(
        address to,
        address,
        uint256 tokenId,
        bytes calldata data
    ) public returns (bytes4) {
        //check if it's the flr registrar ERC721
        if (msg.sender != address(registrar)) {
            revert IncorrectTokenType();
        }

        (
            string memory label,
            address owner,
            uint16 ownerControlledFuses,
            address resolver
        ) = abi.decode(data, (string, address, uint16, address));

        bytes32 labelhash = bytes32(tokenId);
        bytes32 labelhashFromData = keccak256(bytes(label));

        if (labelhashFromData != labelhash) {
            revert LabelMismatch(labelhashFromData, labelhash);
        }

        // transfer the fns record back to the new owner (this contract)
        registrar.reclaim(uint256(labelhash), address(this));

        uint64 expiry = uint64(registrar.nameExpires(tokenId)) + GRACE_PERIOD;

        _wrapETH2LD(label, owner, ownerControlledFuses, expiry, resolver);

        return IERC721Receiver(to).onERC721Received.selector;
    }

    /**
     * @dev Helper pure function to easily generate the node (FNSRegistry) and id (NameWrapper tokenId)
     * @param label - the input name excluding ".flr"
     * @param nodeHash - The node hash that is used in the FNSRegistry
     * @param tokenId - The tokenId used to mint the NameWrapper ERC1155 Token
     */
    function getFLRTokenId(string memory label) external pure returns (bytes32 nodeHash, uint256 tokenId) {
        nodeHash = keccak256(abi.encodePacked(FLR_NODE, keccak256(bytes(label))));
        tokenId = uint256(nodeHash);
    }

    /***** Internal functions */
    function _postTransferAction(
        address from,
        address to,
        uint256 id,
        uint32 fuses,
        uint64 expiry
    ) internal override {
        mintedDomainNamesContract.addFromTransfer(from, to, id, fuses, expiry);
    }

    function _preTransferCheck(
        uint256 id,
        uint32 fuses,
        uint64 expiry
    ) internal view override returns (bool) {
        // For this check, treat .flr 2LDs as expiring at the start of the grace period.
        if (fuses & IS_DOT_ETH == IS_DOT_ETH) {
            expiry -= GRACE_PERIOD;
        }

        if (expiry < block.timestamp) {
            // Transferable if the name was not emancipated
            if (fuses & PARENT_CANNOT_CONTROL != 0) {
                revert("ERC1155: insufficient balance for transfer");
            }
        } else {
            // Transferable if CANNOT_TRANSFER is unburned
            if (fuses & CANNOT_TRANSFER != 0) {
                revert OperationProhibited(bytes32(id));
            }
        }

        return true;
    }

    function _clearOwnerAndFuses(
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal view override returns (address, uint32) {
        if (expiry < block.timestamp) {
            if (fuses & PARENT_CANNOT_CONTROL == PARENT_CANNOT_CONTROL) {
                owner = address(0);
            }
            fuses = 0;
        }

        return (owner, fuses);
    }

    function _makeNode(
        bytes32 node,
        bytes32 labelhash
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(node, labelhash));
    }

    function _addLabel(
        string memory label,
        bytes memory _name
    ) internal pure returns (bytes memory ret) {
        if (bytes(label).length < 1) {
            revert LabelTooShort();
        }
        if (bytes(label).length > 255) {
            revert LabelTooLong(label);
        }
        return abi.encodePacked(uint8(bytes(label).length), label, _name);
    }

    function _mint(
        bytes32 node,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal override {
        _canFusesBeBurned(node, fuses);
        (address oldOwner, , ) = super.getData(uint256(node));
        if (oldOwner != address(0)) {
            // burn and unwrap old token of old owner
            _burn(uint256(node));
            emit NameUnwrapped(node, address(0));
        }
        super._mint(node, owner, fuses, expiry);
    }

    function _wrap(
        bytes32 node,
        bytes memory _name,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry
    ) internal {
        _mint(node, wrappedOwner, fuses, expiry);
        emit NameWrapped(node, _name, wrappedOwner, fuses, expiry);
    }

    function _storeNameAndWrap(
        bytes32 parentNode,
        bytes32 node,
        string memory label,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal {
        bytes memory _name = _addLabel(label, names[parentNode]);
        _wrap(node, _name, owner, fuses, expiry);
    }

    function _saveLabel(
        bytes32 parentNode,
        bytes32 node,
        string memory label
    ) internal returns (bytes memory) {
        bytes memory _name = _addLabel(label, names[parentNode]);
        names[node] = _name;
        return _name;
    }

    function _updateName(
        bytes32 parentNode,
        bytes32 node,
        string memory label,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal {
        (address oldOwner, uint32 oldFuses, uint64 oldExpiry) = getData(
            uint256(node)
        );
        bytes memory _name = _addLabel(label, names[parentNode]);
        if (names[node].length == 0) {
            names[node] = _name;
        }
        _setFuses(node, oldOwner, oldFuses | fuses, oldExpiry, expiry);
        if (owner == address(0)) {
            _unwrap(node, address(0));
        } else {
            _transfer(oldOwner, owner, uint256(node), 1, "");
        }
    }

    // wrapper function for stack limit
    function _checkParentFusesAndExpiry(
        bytes32 parentNode,
        bytes32 node,
        uint32 fuses,
        uint64 expiry
    ) internal view returns (uint64) {
        (, , uint64 oldExpiry) = getData(uint256(node));
        (, uint32 parentFuses, uint64 maxExpiry) = getData(uint256(parentNode));
        _checkParentFuses(node, fuses, parentFuses);
        return _normaliseExpiry(expiry, oldExpiry, maxExpiry);
    }

    function _checkParentFuses(
        bytes32 node,
        uint32 fuses,
        uint32 parentFuses
    ) internal pure {
        bool isBurningParentControlledFuses = fuses & PARENT_CONTROLLED_FUSES !=
            0;

        bool parentHasNotBurnedCU = parentFuses & CANNOT_UNWRAP == 0;

        if (isBurningParentControlledFuses && parentHasNotBurnedCU) {
            revert OperationProhibited(node);
        }
    }

    function _normaliseExpiry(
        uint64 expiry,
        uint64 oldExpiry,
        uint64 maxExpiry
    ) internal pure returns (uint64) {
        // Expiry cannot be more than maximum allowed
        // .flr names will check registrar, non .flr check parent
        if (expiry > maxExpiry) {
            expiry = maxExpiry;
        }
        // Expiry cannot be less than old expiry
        if (expiry < oldExpiry) {
            expiry = oldExpiry;
        }

        return expiry;
    }

    function _wrapETH2LD(
        string memory label,
        address wrappedOwner,
        uint32 fuses,
        uint64 expiry,
        address resolver
    ) private {
        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = _makeNode(FLR_NODE, labelhash);
        // hardcode dns-encoded flr string for gas savings
        bytes memory _name = _addLabel(label, "\x03flr\x00");
        names[node] = _name;

        // uint256(node) is the tokenId when mint is called
        mintedDomainNamesContract.add(wrappedOwner, uint256(node), fuses, expiry, label);

        _wrap(
            node,
            _name,
            wrappedOwner,
            fuses | PARENT_CANNOT_CONTROL | IS_DOT_ETH,
            expiry
        );

        if (resolver != address(0)) {
            fns.setResolver(node, resolver);
        }
    }

    function _unwrap(bytes32 node, address owner) private {
        if (allFusesBurned(node, CANNOT_UNWRAP)) {
            revert OperationProhibited(node);
        }

        // Burn token and fuse data
        _burn(uint256(node));
        fns.setOwner(node, owner);

        emit NameUnwrapped(node, owner);
    }

    function _setFuses(
        bytes32 node,
        address owner,
        uint32 fuses,
        uint64 oldExpiry,
        uint64 expiry
    ) internal {
        _setData(node, owner, fuses, expiry);
        emit FusesSet(node, fuses);
        if (expiry > oldExpiry) {
            emit ExpiryExtended(node, expiry);
        }
    }

    function _setData(
        bytes32 node,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal {
        _canFusesBeBurned(node, fuses);
        super._setData(uint256(node), owner, fuses, expiry);
    }

    function _canFusesBeBurned(bytes32 node, uint32 fuses) internal pure {
        // If a non-parent controlled fuse is being burned, check PCC and CU are burnt
        if (
            fuses & ~PARENT_CONTROLLED_FUSES != 0 &&
            fuses & (PARENT_CANNOT_CONTROL | CANNOT_UNWRAP) !=
            (PARENT_CANNOT_CONTROL | CANNOT_UNWRAP)
        ) {
            revert OperationProhibited(node);
        }
    }

    function _checkFusesAreSettable(bytes32 node, uint32 fuses) internal pure {
        if (fuses | USER_SETTABLE_FUSES != USER_SETTABLE_FUSES) {
            // Cannot directly burn other non-user settable fuses
            revert OperationProhibited(node);
        }
    }

    function _isWrapped(bytes32 node) internal view returns (bool) {
        return
            ownerOf(uint256(node)) != address(0) &&
            fns.owner(node) == address(this);
    }
}
