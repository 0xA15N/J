pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "fns/registry/FNSRegistry.sol";
import "fns/resolvers/PublicResolver.sol";
import "fns/flr-registrar/BaseRegistrar.sol";
import "fns/chain-state/MintedDomainNames.sol";
import "fns/chain-state/IMintedDomainNames.sol";
import "fns/registry/ReverseRegistrar.sol";
import "fns/wrapper/NameWrapper.sol";
import "fns/wrapper/StaticMetadataService.sol";
import "fns/flr-registrar/FLRRegistrarController.sol";
import "fns/flr-registrar/mock/MockStablePriceOracle.sol";
import "fns/flr-registrar/DummyOracle.sol";
import "fns/no-collisions/NoNameCollisions.sol";

import {DeployFNSAbstract} from "./DeployFNSAbstract.s.sol";

import "fns-test/utils/FNSNamehash.sol";

contract Template is Script, DeployFNSAbstract {
    function run() external {
        uint256 broadcastPrivKey = ANVIL_OWNER_PRIVATE_KEY;
        address broadcastAddress = ANVIL_OWNER_ADDRESS;
        string memory name = "test";

        vm.startBroadcast(broadcastPrivKey);

        bytes32 commitment = flrRegistrarController.makeCommitment(
            name,
            broadcastAddress,
            31556952,
            keccak256(bytes(name)),
            address(publicResolver),
            new bytes[](0),
            true,
            0);
        
        console.logBytes32(commitment);
        flrRegistrarController.commit(commitment);
        
        console.log("Before Warp: block.timestamp = %s", block.timestamp);
        vm.warp(block.timestamp + 600);
        console.log("After Warp: block.timestamp = %s", block.timestamp);

        IPriceOracle.Price memory price = flrRegistrarController.rentPrice(name, 31556952);
        uint256 totalPrice = price.base + price.premium;

        console.log("Price of name:%s => %s", name, totalPrice);

        flrRegistrarController.register{ value: totalPrice }(
            name,
            broadcastAddress,
            31556952,
            keccak256(bytes(name)),
            address(publicResolver),
            new bytes[](0),
            true,
            0);
        
        (bytes32 nodeId, uint tokenId) = nameWrapper.getFLRTokenId(name);
        console.logBytes32(nodeId);
        console.log("tokenId=%s", tokenId);

        bytes memory emptyBytes;
        nameWrapper.safeTransferFrom(broadcastAddress, DEPLOYER_ADDRESS, tokenId, 1, emptyBytes);
        
        (IMintedDomainNames.Data[] memory data, uint256 length) = mintedDomainNames.getAll(broadcastAddress);
        console.log("MintedDomainNames length=%s", length);
        for(uint i = 0; i < length; ++i){
            console.log("data[%s]\n\tid=%s\n\texpiry=%s\n\t", i, data[i].id, data[i].expiry);
            console.logString(data[i].label);
        }

        (data, length) = mintedDomainNames.getAll(DEPLOYER_ADDRESS);
        console.log("MintedDomainNames length=%s", length);
        for(uint i = 0; i < length; ++i){
            console.log("data[%s]\n\tid=%s\n\texpiry=%s\n\t", i, data[i].id, data[i].expiry);
            console.logString(data[i].label);
        }

        // Check the set name
        string memory reverseName = publicResolver.name(reverseRegistrar.node(broadcastAddress));
        console.log("NAME SET FOR: %s", broadcastAddress);
        console.logString(reverseName);
        
        vm.stopBroadcast();

        // Now set the name for the new owner
        vm.startBroadcast(ANVIL_DEPLOYER_PRIVATE_KEY);
        bytes32 node = reverseRegistrar.setName(name);
        reverseName = publicResolver.name(node);
        console.log("NAME SET FOR: %s", ANVIL_DEPLOYER_ADDRESS);
        console.logString(reverseName);
        vm.stopBroadcast();
    }
}