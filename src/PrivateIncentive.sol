// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IncentiveBase.sol";
import "./SmartWallet.sol";
import "openzeppelin/contracts/proxy/Clones.sol";

abstract contract PrivateIncentive is IncentiveBase {
    using SafeTransferLib for ERC20;

    address public immutable TEMPLATE;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

        TEMPLATE = address(new SmartWallet(address(this)));
    }

    //All private contracts can inherit this function. They would differ in the (re)claim functions.
    function incentivize(bytes32 incentiveId, bytes calldata incentiveInfo) external virtual payable {
        //Make sure the committment is the same as the data they provided.
        require(incentives[incentiveId].timestamp == 0, "incentive already exists");

        //Create the new incentive object with the limited available information
        Incentive memory incentive;
        incentive.incentivizer = msg.sender;
        incentive.timestamp = uint96(block.timestamp); //this downcast is safe

        //Place in storage 
        incentives[incentiveId] = incentive;

        //The encrypted data is emitted as an event
        emit incentiveSent(msg.sender, address(0), 0, address(0), incentiveInfo);
    }

    function retrieveTokens(Incentive memory incentive) internal virtual {
        //The salt is the keccak256 of all the previously hidden info
        bytes32 salt = keccak256(abi.encode(incentive.recipient, 
                                            incentive.incentiveToken, 
                                            incentive.amount, 
                                            incentive.proposalId,
                                            incentive.direction));

        address wallet = Clones.predictDeterministicAddress(TEMPLATE, salt);
        require(wallet.code.length > 0, "Smart Wallet already exists"); //Make sure the address doesn't already exists so the create2Fails

        //Create the wallet and send the tokens to this where they can be distributed
        wallet = Clones.cloneDeterministic(TEMPLATE, salt);
        SmartWallet(wallet).sendTokens(address(this), incentive.amount);
    }

}