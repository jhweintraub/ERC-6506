// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IncentiveBase.sol";
import "./SmartWallet.sol";
import "openzeppelin/contracts/proxy/Clones.sol";

import "forge-std/console.sol";

abstract contract PrivateIncentive is IncentiveBase {
    using SafeTransferLib for ERC20;

    address public immutable TEMPLATE;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {
        TEMPLATE = address(new SmartWallet(address(this)));
    }

    //All private contracts can inherit this function. They would differ in the (re)claim functions.
    function incentivize(bytes32 incentiveId, bytes memory incentiveInfo) external virtual payable {
        require(incentives[incentiveId].timestamp == 0, "incentive already exists");

        //Create the new incentive object with the limited available information
        Incentive memory incentive;
        incentive.incentivizer = msg.sender;
        incentive.timestamp = uint96(block.timestamp); //this downcast is safe

        console.log("incentivizer: ", incentive.incentivizer);
        //Place in storage 
        incentives[incentiveId] = incentive;

        //The encrypted data is emitted as an event
        emit incentiveSent(msg.sender, address(0), 0, address(0), incentiveInfo);
    }

    function validateReveal(bytes32 incentiveId, bytes memory reveal) internal virtual returns (Incentive memory) {
        (address incentiveToken,
        address recipient,
        address incentivizer,
        uint amount,
        uint256 proposalId,
        bytes32 direction, //the keccack256 of the vote direction
        uint96 deadline) = abi.decode(reveal, (address, address, address, uint, uint256, bytes32, uint96));

        bytes32 revealHash = keccak256(reveal);
        require(revealHash == incentiveId, "data provided does not match committment");

        //Verify that they revealed the info for an already committed-to incentive.        
        Incentive storage incentive = incentives[revealHash];
        require(incentive.timestamp > 0, "no incentive exists for provided data");

        //Store the revealed data in long-term storage
        incentive.incentiveToken = incentiveToken;
        incentive.amount = amount;
        incentive.incentivizer = incentivizer;
        incentive.proposalId = proposalId;
        incentive.direction = direction;
        incentive.deadline = deadline;
        incentive.recipient = recipient;

        return incentive;
    }

    function retrieveTokens(Incentive memory incentive) internal virtual {
        (address wallet, bytes32 salt) = predictDeterministic(incentive);

        require(wallet.code.length == 0, "Smart Wallet already exists"); //Make sure the address doesn't already exists so the create2Fails
        //Create the wallet and send the tokens to this where they can be distributed
        wallet = Clones.cloneDeterministic(TEMPLATE, salt);
        SmartWallet(wallet).sendTokens(incentive.incentiveToken, incentive.amount);
    }

    function predictDeterministic(Incentive memory incentive) public view returns (address smartWallet, bytes32 salt){
        //The salt is the keccak256 of all the previously hidden info but in a different order than the incentiveId
        salt = keccak256(abi.encode(incentive.amount,                                    
                                    incentive.incentivizer,
                                    incentive.proposalId,
                                    incentive.recipient, 
                                    incentive.incentiveToken,
                                    incentive.deadline,
                                    incentive.direction));

        smartWallet = Clones.predictDeterministicAddress(TEMPLATE, salt);
    }

}