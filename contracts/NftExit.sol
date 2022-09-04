// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TODO: Add fees, expiry

contract NftExit {
    /* List contract flow: 
    Alice: proveOwnership -> transferContract to NftExit -> listContract 
    Bob: acceptAsk
    */
    /* Bid contract flow:
    Bob: placeBid
    Alice: proveOwnership -> transferContract to NftExit -> acceptBid
    */

    address public WETH;

    struct Offer {
        address Maker;
        bool isBid;
        address Contract;
        address Taker;
        uint256 Amount;
    }

    mapping(bytes32 => Offer) public Offers;
    mapping(address => address) public originalOwner;

    constructor() {
        // WETH
        WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    }

    function ownerOfContract(address _contract) public view returns (address) {
         Ownable externalContract = Ownable(_contract);
         return externalContract.owner();
    }

    function proveOwnership(address _contract) public {
        Ownable externalContract = Ownable(_contract);
        address _owner = externalContract.owner();
        require(_owner == msg.sender, "You don't own this contract");

        originalOwner[_contract] = msg.sender;
    }

    function placeBid(uint256 amount, address _contract) public {
        // Retrieve external contract's owner. Contract changing hands invalidates the bid.
        Ownable externalContract = Ownable(_contract);
        address _owner = externalContract.owner();

        require(msg.sender != _owner, "Can't bid for your own contract");
        
        bytes32 bidId = hashOffer(msg.sender, _contract, true);
        require(Offers[bidId].Maker != address(0), "Can't bid twice for the same contract");
        
        // Check allowance
        // User would approve allowance within our frontend before initiating this
        require(IERC20(WETH).allowance(msg.sender, address(this)) >= amount, "Must approve to spend before placing the bid");
        require(IERC20(WETH).balanceOf(msg.sender) >= amount, "Insufficient funds");

        // Create new bid
        Offers[bidId].Maker = msg.sender;
        Offers[bidId].Contract = _contract;
        Offers[bidId].Amount = amount;
        Offers[bidId].isBid = true;
    }

    function removeBid(bytes32 bidId) public {
        /* Validation */
        require(msg.sender == Offers[bidId].Maker, "Can't cancel others' orders");

        /* Effects */
        delete Offers[bidId];
    }

    function withdrawContract(address _contract) public {
        Ownable externalContract = Ownable(_contract);
        address _owner = externalContract.owner();

        require(_owner == address(this), "Contract hasn't been locked");
        require(originalOwner[_contract] == msg.sender, "You are not the original owner of this contract");

        // Delete asks if exist
        bytes32 askId = hashOffer(msg.sender, _contract, false);
        delete Offers[askId];

        // Withdraw the contract
        externalContract.transferOwnership(msg.sender);
    }

    function modifyOfferPrice(bytes32 offerId, uint256 amount) public {
        require(Offers[offerId].Maker == msg.sender, "Not your contract");
        Offers[offerId].Amount = amount;
    }

    // UTILS:
    function hashOffer(address maker, address taker, bool isBid) public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(maker, taker, isBid));
    }

    // Can also be used to modify the offer
    function listContract(uint256 amount, address _contract) public {
        require(originalOwner[_contract] == msg.sender, "You are not the original owner of this contract");
        require(Ownable(_contract).owner() == address(this));

        bytes32 askId = hashOffer(msg.sender, _contract, false);

        // Create new ask
        Offers[askId].Maker = msg.sender;
        Offers[askId].Contract = _contract;
        Offers[askId].Amount = amount;
        Offers[askId].isBid = false;
    }

    function acceptBid(bytes32 bidId, uint256 amount) public {
        address _contract = Offers[bidId].Contract;

        Ownable externalContract = Ownable(_contract);
        address _owner = externalContract.owner();
        require(address(this) == _owner, "Must transfer the contract before accepting the bid");

        /* Validation */
        // Require the owner to have sent the contract to us.
        require(originalOwner[_contract] == msg.sender, "You are not the original owner of this contract");
        
        // Validate bid authenticity 
        address _buyer = Offers[bidId].Maker;
        bytes32 _id = hashOffer(_buyer, _contract, true);
        require(_id == bidId, "Bids mismatch");
        require(Offers[bidId].Amount == amount);

        // Check allowance
        require(IERC20(WETH).allowance(_buyer, address(this)) >= Offers[bidId].Amount, "Insufficient funds");

        /* Effects */
        // Delete the bid.
        delete Offers[bidId];

        /* Interactions */
        // Trade the contract in exchange for the bid amount
        IERC20(WETH).transferFrom(_buyer, msg.sender, Offers[bidId].Amount);
        externalContract.transferOwnership(_buyer);
    }

    function acceptAsk(bytes32 askId, uint256 amount) public {
        address _contract = Offers[askId].Contract;

        Ownable externalContract = Ownable(_contract);
        address _owner = externalContract.owner();
        require(address(this) == _owner, "Must transfer the contract before accepting the bid");

        // Check allowance
        // User would approve allowance within our frontend before initiating this
        require(IERC20(WETH).allowance(msg.sender, address(this)) >= Offers[askId].Amount, "Must approve to spend before placing the bid");
        require(IERC20(WETH).balanceOf(msg.sender) >= Offers[askId].Amount, "Insufficient funds");

        // Validate ask authenticity 
        address _buyer = Offers[askId].Maker;
        bytes32 _id = hashOffer(_buyer, _contract, false);
        require(_id == askId, "Bids mismatch");
        require(Offers[askId].Amount == amount);

        /* Effects */
        // Delete the bid.
        delete Offers[askId];

        /* Interactions */
        // Trade the contract in exchange for the ask amount
        IERC20(WETH).transferFrom(msg.sender, Offers[askId].Maker, Offers[askId].Amount);

        externalContract.transferOwnership(msg.sender);
    }
}

