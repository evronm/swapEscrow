// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EscrowFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        EscrowFactory factory = new EscrowFactory();

        console.log("EscrowFactory deployed at:", address(factory));
        console.log("Escrow implementation at:", factory.escrowImplementation());

        vm.stopBroadcast();

        // Write deployment info to file
        string memory chainId = vm.toString(block.chainid);
        string memory deployment = string(abi.encodePacked(
            '{\n',
            '  "chainId": ', chainId, ',\n',
            '  "factory": "', vm.toString(address(factory)), '",\n',
            '  "implementation": "', vm.toString(factory.escrowImplementation()), '"\n',
            '}'
        ));

        string memory filename = string(abi.encodePacked("deployments/chain-", chainId, ".json"));
        vm.writeFile(filename, deployment);
        console.log("Deployment info written to:", filename);
    }
}
