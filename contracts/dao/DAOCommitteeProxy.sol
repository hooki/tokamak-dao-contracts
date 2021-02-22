// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./StorageStateCommittee.sol";
//import "../../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../../node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import { ERC165 } from "../../node_modules/@openzeppelin/contracts/introspection/ERC165.sol";

contract DAOCommitteeProxy is StorageStateCommittee, AccessControl, ERC165 {
    address public _implementation;
    bool public pauseProxy;

    event Upgraded(address indexed implementation);

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "DAOCommitteeProxy: msg.sender is not an admin");
        _;
    }
     
    constructor(
        address _ton,
        address _impl,
        address _seigManager,
        address _layer2Registry,
        address _agendaManager,
        address _candidateFactory,
        //address _activityRewardManager,
        address _daoVault
    )
    {
        ton = _ton;
        _implementation = _impl;
        seigManager = ISeigManager(_seigManager);
        layer2Registry = ILayer2Registry(_layer2Registry);
        agendaManager = IDAOAgendaManager(_agendaManager);
        candidateFactory = ICandidateFactory(_candidateFactory);
        daoVault = IDAOVault(_daoVault);
        quorum = 2;
        activityRewardPerSecond = 1e18;

        _registerInterface(bytes4(keccak256("onApprove(address,address,uint256,bytes)")));
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    /// @notice Set pause state
    /// @param _pause true:pause or false:resume
    function setProxyPause(bool _pause) external onlyOwner {
        pauseProxy = _pause;
    }

    /// @notice Set implementation contract
    /// @param impl New implementation contract address
    function upgradeTo(address impl) external onlyOwner {
        require(_implementation != impl, "DAOCommitteeProxy: implementation address is zero");
        _implementation = impl;
        emit Upgraded(impl);
    }

    function implementation() public view returns (address) {
        return _implementation;
    }

    fallback() external {
        _fallback();
    }

    function _fallback() internal {
        address _impl = implementation();
        require(_impl != address(0) && !pauseProxy, "DAOCommitteeProxy: impl is zero OR proxy is false");

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
