// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./lib/ERC20.sol";
import "./lib/SafeTransferLib.sol";

contract SmartWallet {
    using SafeTransferLib for ERC20;

    address public immutable DEPLOYER;

    constructor(address _deployer) {
        DEPLOYER = _deployer;
    }

    function sendTokens(address token, uint amount) external onlyDeployer {
        //Hard-coding in send to deployer is an anti-rug vector since the deployer cannot make arbitrary calls like this
        ERC20(token).safeTransfer(DEPLOYER, amount);
    }


    modifier onlyDeployer {
        require(msg.sender == DEPLOYER, "only master deployer can access this function");
        _;
    }
}