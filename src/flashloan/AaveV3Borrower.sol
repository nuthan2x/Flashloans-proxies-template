// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAddressesProvider, IFlashLoanReceiver, IPool} from "./interfaces/IAaveV3Interfaces.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AaveV3Borrower is Ownable, IFlashLoanReceiver{
    using SafeERC20 for IERC20;

    IPoolAddressesProvider public override ADDRESSES_PROVIDER;
    IPool public override POOL;

    constructor(IPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
    }

    receive() external payable {}


    function transferOutEth() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function transferOutTokens(address[] calldata tokens) external onlyOwner {
        uint i = 0;
        for (; i < tokens.length; ) {
            uint balance = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).transfer(owner(), balance);

            unchecked {
                ++i;
            }
        }
    }

    function changePool(IPoolAddressesProvider provider) external onlyOwner {
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
    }

    function requestFlashLoan(
        address[] calldata assets,
        uint256[] calldata amounts, 
        bytes calldata params
    ) external payable onlyOwner{
        address receiverAddress = address(this);
        uint256[] memory interestRateModes = new uint256[](assets.length);
        address onBehalfOf = address(this);
        uint16 referralCode = 0;

        POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            interestRateModes,
            onBehalfOf,
            params,
            referralCode
        );
    }
    
    function  executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )  external override returns (bool) {
        require(initiator == address(this), "wrong initiator");
        require(msg.sender == address(POOL), "wrong caller");

        // logic
        {
            (address target, uint256 value) = abi.decode(params, (address, uint256));
            bytes memory txData =  
                abi.encodeWithSignature("receiveCall(address[],uint256[],uint256[])", assets, amounts, premiums);

            (bool success,) = target.call{value : value}(txData);
            require(success, "target call failed");
        }

        // approving to return funds
        uint i = 0;
        for (; i < assets.length; ) {
            uint256 totalAmount = amounts[i] + premiums[i];
            IERC20(assets[i]).safeApprove(address(POOL), totalAmount);

            unchecked {
                ++i;
            }
        }

        return true;
    }
}
