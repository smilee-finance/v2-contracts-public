// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is EpochControls, ERC20, IVault {
    using SafeMath for uint256;
    using VaultLib for VaultLib.DepositReceipt;

    address public immutable dvp;
    address public immutable baseToken;
    address public immutable sideToken;

    VaultLib.VaultState public vaultState;
    mapping(address => VaultLib.DepositReceipt) public depositReceipts;
    mapping(uint256 => uint256) public epochPricePerShare;

    error OnlyDVPAllowed();
    error AmountZero();
    error LiquidityIsLocked();
    error SecondaryMarkedNotAllowed();

    constructor(IDVP dvp_, address baseToken_, address sideToken_) EpochControls(dvp_.epochFrequency()) ERC20("", "") {
        dvp = address(dvp_);
        baseToken = baseToken_;
        sideToken = sideToken_;
    }

    modifier onlyDVP() {
        if (msg.sender != dvp) {
            revert OnlyDVPAllowed();
        }
        _;
    }

    function getPortfolio() public view override returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = IERC20(baseToken).balanceOf(address(this));
        sideTokenAmount = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function deposit(uint256 amount) external override epochActive {
        if (!(amount > 0)) {
            revert AmountZero();
        }

        address creditor = msg.sender;

        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[creditor];

        // If a user deposited in the past and never redeemed her shares, update her receipt with the shares
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
        );

        uint256 depositAmount = amount;

        // If the user has already deposited in the current epoch, add the amount to the pending deposit
        if (currentEpoch == depositReceipt.epoch) {
            uint256 newAmount = uint256(depositReceipt.amount).add(amount);
            depositAmount = newAmount;
        }

        depositReceipts[creditor] = VaultLib.DepositReceipt({
            epoch: currentEpoch,
            amount: depositAmount,
            unredeemedShares: unredeemedShares
        });
        vaultState.totalPendingLiquidity = vaultState.totalPendingLiquidity.add(amount);

        IERC20(baseToken).transferFrom(msg.sender, address(this), amount);
    }

    function rollEpoch() public override {
        // assume locked liquidity is updated after trades

        uint256 sharePrice;
        if (totalSupply() == 0) {
            // first time mint 1:1
            sharePrice = 10 ** VaultLib.DECIMALS;
        } else {
            if (vaultState.lockedLiquidity > 0) {
                sharePrice = vaultState.lockedLiquidity / totalSupply();
            } else {
                // if locked liquidity goes to 0 (market crash) need to burn all shares supply
                // TODO
            }
        }

        epochPricePerShare[currentEpoch] = sharePrice;
        uint256 sharesToMint = VaultLib.assetToShares(vaultState.totalPendingLiquidity, sharePrice);
        _mint(address(this), sharesToMint);
        vaultState.lockedLiquidity = vaultState.lockedLiquidity.add(vaultState.totalPendingLiquidity);
        vaultState.totalPendingLiquidity = 0;
        super.rollEpoch();
    }

    /// @inheritdoc IVault
    function shareBalances(address account) public view override returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        if (!(depositReceipt.epoch > 0)) {
            return (0, 0);
        }

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            currentEpoch,
            epochPricePerShare[depositReceipt.epoch]
        );
        return (balanceOf(account), unredeemedShares);
    }

    /**
        @dev Block shares transfer when not allowed (for testnet purposes)
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        amount;
        if (from == address(0) || to == address(0)) {
            // it's a valid mint/burn
            return;
        }
        revert SecondaryMarkedNotAllowed();
    }
}
