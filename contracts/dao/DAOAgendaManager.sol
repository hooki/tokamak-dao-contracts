// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMath } from "../../node_modules/@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from  "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDAOCommittee } from "../interfaces/IDAOCommittee.sol";
import { ICandidate } from "../interfaces/ICandidate.sol";
import { LibAgenda } from "../lib/Agenda.sol";
import "../../node_modules/@openzeppelin/contracts/access/Ownable.sol";

contract DAOAgendaManager is Ownable {
    using SafeMath for uint256;
    using LibAgenda for *;

    enum VoteChoice { ABSTAIN, YES, NO, MAX }

    IDAOCommittee public committee;
    
    uint256 public createAgendaFees; // 아젠다생성비용(TON)
    
    uint256 public minimumNoticePeriodSeconds;
    uint256 public minimumVotingPeriodSeconds;
    uint256 public executingPeriodSeconds;
    
    LibAgenda.Agenda[] public agendas;
    mapping(uint256 => mapping(address => LibAgenda.Voter)) public voterInfos;
    mapping(uint256 => LibAgenda.AgendaExecutionInfo) internal executionInfos;
    
    event AgendaStatusChanged(
        uint256 indexed agendaID,
        uint256 prevStatus,
        uint256 newStatus
    );

    event AgendaResultChanged(
        uint256 indexed agendaID,
        uint256 result
    );

    modifier validAgenda(uint256 _agendaID) {
        require(_agendaID < agendas.length, "DAOAgendaManager: invalid agenda id");
        _;
    }
    
    constructor() {
        minimumNoticePeriodSeconds = 60 * 60 * 24 * 15; //  15 days, on seconds
        minimumVotingPeriodSeconds = 60 * 60 * 24 * 2; //  2 days, on seconds
        executingPeriodSeconds = 60 * 60 * 24 * 7; //  7 days, on seconds
        
        createAgendaFees = 100000000000000000000; // 100 TON
    }

    function getStatus(uint _status) public pure returns (LibAgenda.AgendaStatus emnustatus) {
        if (_status == uint(LibAgenda.AgendaStatus.NOTICE))
            return LibAgenda.AgendaStatus.NOTICE;
        else if (_status == uint(LibAgenda.AgendaStatus.VOTING))
            return LibAgenda.AgendaStatus.VOTING;
        else if (_status == uint(LibAgenda.AgendaStatus.EXECUTED))
            return LibAgenda.AgendaStatus.EXECUTED;
        else if (_status == uint(LibAgenda.AgendaStatus.ENDED))
            return LibAgenda.AgendaStatus.ENDED;
        else
            return LibAgenda.AgendaStatus.NONE;
    }

    /// @notice Set DAOCommitteeProxy contract address
    /// @param _committee New DAOCommitteeProxy contract address
    function setCommittee(address _committee) public onlyOwner {
        require(_committee != address(0), "DAOAgendaManager: address is zero");
        committee = IDAOCommittee(_committee);
    }

    /// @notice Set status of the agenda
    /// @param _agendaID agenda ID
    /// @param _status New status of the agenda
    function setStatus(uint256 _agendaID, uint _status) public onlyOwner {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Proposal Id");

        emit AgendaStatusChanged(_agendaID, uint(agendas[_agendaID].status), _status);
        agendas[_agendaID].status = getStatus(_status);
    }

    /// @notice Set the fee(TON) of creating an agenda
    /// @param _createAgendaFees New fee(TON)
    function setCreateAgendaFees(uint256 _createAgendaFees) public onlyOwner {
        createAgendaFees = _createAgendaFees;
    }

    /// @notice Set the minimum notice period in seconds
    /// @param _minimumNoticePeriodSeconds New minimum notice period in seconds
    function setMinimumNoticePeriodSeconds(uint256 _minimumNoticePeriodSeconds) public onlyOwner {
        minimumNoticePeriodSeconds = _minimumNoticePeriodSeconds;
    }

    /// @notice Set the executing period in seconds
    /// @param _executingPeriodSeconds New executing period in seconds
    function setExecutingPeriodSeconds(uint256 _executingPeriodSeconds) public onlyOwner {
        executingPeriodSeconds = _executingPeriodSeconds;
    }

    /// @notice Set the minimum voting period in seconds
    /// @param _minimumVotingPeriodSeconds New minimum voting period in seconds
    function setMinimumVotingPeriodSeconds(uint256 _minimumVotingPeriodSeconds) public onlyOwner {
        minimumVotingPeriodSeconds = _minimumVotingPeriodSeconds;
    }
      
    /// @notice Creates an agenda
    /// @param _targets Target addresses for executions of the agenda
    /// @param _noticePeriodSeconds Notice period in seconds
    /// @param _votingPeriodSeconds Voting period in seconds
    /// @param _functionBytecodes RLP-Encoded parameters for executions of the agenda
    /// @return agendaID Created agenda ID
    function newAgenda(
        address[] calldata _targets,
        uint256 _noticePeriodSeconds,
        uint256 _votingPeriodSeconds,
        bytes[] calldata _functionBytecodes
    )
        onlyOwner
        public
        returns (uint256 agendaID)
    {
        require(
            _noticePeriodSeconds >= minimumNoticePeriodSeconds,
            "DAOAgendaManager: minimumNoticePeriod is short"
        );

        agendaID = agendas.length;
         
        address[] memory emptyArray;
        agendas.push(LibAgenda.Agenda({
            status: LibAgenda.AgendaStatus.NOTICE,
            result: LibAgenda.AgendaResult.PENDING,
            executed: false,
            createdTimestamp: block.timestamp,
            noticeEndTimestamp: block.timestamp + _noticePeriodSeconds,
            votingPeriodInSeconds: _votingPeriodSeconds,
            votingStartedTimestamp: 0,
            votingEndTimestamp: 0,
            executableLimitTimestamp: 0,
            executedTimestamp: 0,
            countingYes: 0,
            countingNo: 0,
            countingAbstain: 0,
            voters: emptyArray
        }));

        LibAgenda.AgendaExecutionInfo storage executionInfo = executionInfos[agendaID];
        for (uint256 i = 0; i < _targets.length; i++) {
            executionInfo.targets.push(_targets[i]);
            executionInfo.functionBytecodes.push(_functionBytecodes[i]);
        }

        //numAgendas = agendas.length;
        //agendaID = numAgendas.sub(1);
    }

    /// @notice Casts vote for an agenda
    /// @param _agendaID Agenda ID
    /// @param _voter Voter
    /// @param _vote Voting type
    /// @return Whether or not the execution succeeded
    function castVote(
        uint256 _agendaID,
        address _voter,
        uint _vote
    )
        public
        onlyOwner
        returns (bool)
    {
        require(_vote < uint(VoteChoice.MAX), "DAOAgendaManager: invalid vote");

        require(
            isVotableStatus(_agendaID),
            "DAOAgendaManager: invalid status"
        );

        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        if (agenda.status == LibAgenda.AgendaStatus.NOTICE) {
            _startVoting(_agendaID);
        }

        require(isVoter(_agendaID, _voter), "DAOAgendaManager: not a voter");
        require(!hasVoted(_agendaID, _voter), "DAOAgendaManager: already voted");

        require(
            block.timestamp <= agenda.votingEndTimestamp,
            "DAOAgendaManager: for this agenda, the voting time expired"
        );
        
        LibAgenda.Voter storage voter = voterInfos[_agendaID][_voter];
        voter.hasVoted = true;
        voter.vote = _vote;
             
        // counting 0:abstainVotes 1:yesVotes 2:noVotes
        if (_vote == uint(VoteChoice.ABSTAIN))
            agenda.countingAbstain = agenda.countingAbstain.add(1);
        else if (_vote == uint(VoteChoice.YES))
            agenda.countingYes = agenda.countingYes.add(1);
        else if (_vote == uint(VoteChoice.NO))
            agenda.countingNo = agenda.countingNo.add(1);
        else
            revert();
        
        return true;
    }
    
    /// @notice Set the agenda status as executed
    /// @param _agendaID Agenda ID
    function setExecutedAgenda(uint256 _agendaID)
        public
        onlyOwner
    {
        require(_agendaID < agendas.length, "DAOAgendaManager: _agendaID is invalid.");

        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        agenda.executed = true;
        agenda.executedTimestamp = block.timestamp;

        emit AgendaStatusChanged(_agendaID, uint(agenda.status), uint(LibAgenda.AgendaStatus.EXECUTED));

        agenda.status = LibAgenda.AgendaStatus.EXECUTED;
    }

    /// @notice Set the agenda result
    /// @param _agendaID Agenda ID
    /// @param _result New result
    function setResult(uint256 _agendaID, LibAgenda.AgendaResult _result)
        public
        onlyOwner
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        agenda.result = _result;

        emit AgendaResultChanged(_agendaID, uint256(_result));
    }
     
    /// @notice Set the agenda status
    /// @param _agendaID Agenda ID
    /// @param _status New status
    function setStatus(uint256 _agendaID, LibAgenda.AgendaStatus _status)
        public
        onlyOwner
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        emit AgendaStatusChanged(_agendaID, uint256(agenda.status), uint256(_status));
        agenda.status = _status;
    }

    /// @notice Set the agenda status as ended(denied or dismissed)
    /// @param _agendaID Agenda ID
    function endAgendaVoting(uint256 _agendaID)
        public
        onlyOwner
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        require(
            agenda.status == LibAgenda.AgendaStatus.VOTING,
            "DAOAgendaManager: agenda status is not changable"
        );

        require(
            agenda.votingEndTimestamp <= block.timestamp,
            "DAOAgendaManager: voting is not ended yet"
        );

        setStatus(_agendaID, LibAgenda.AgendaStatus.ENDED);
        setResult(_agendaID, LibAgenda.AgendaResult.DISMISS);
    }
     
    function _startVoting(uint256 _agendaID) internal {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        agenda.votingStartedTimestamp = block.timestamp;
        agenda.votingEndTimestamp = block.timestamp.add(agenda.votingPeriodInSeconds);
        agenda.executableLimitTimestamp = agenda.votingEndTimestamp.add(executingPeriodSeconds);
        agenda.status = LibAgenda.AgendaStatus.VOTING;

        uint256 memberCount = committee.maxMember();
        for (uint256 i = 0; i < memberCount; i++) {
            address voter = committee.members(i);
            agenda.voters.push(voter);
            voterInfos[_agendaID][voter].isVoter = true;
        }

        emit AgendaStatusChanged(_agendaID, uint(LibAgenda.AgendaStatus.NOTICE), uint(LibAgenda.AgendaStatus.VOTING));
    }
    
    function isVoter(uint256 _agendaID, address _candidate) public view returns (bool) {
        require(_candidate != address(0), "DAOAgendaManager: user address is zero");
        return voterInfos[_agendaID][_candidate].isVoter;
    }
    
    function hasVoted(uint256 _agendaID, address _user) public view returns (bool) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Proposal Id");
        return voterInfos[_agendaID][_user].hasVoted;
    }

    function getVoteStatus(uint256 _agendaID, address _user) public view returns (bool, uint256) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Proposal Id");
        
        LibAgenda.Voter storage voter = voterInfos[_agendaID][_user];

        return (
            voter.hasVoted,
            voter.vote
        );
    }
    
    function getAgendaNoticeEndTimeSeconds(uint256 _agendaID) public view returns (uint) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Agenda Id");
        return agendas[_agendaID].noticeEndTimestamp;
    }
    
    function getAgendaVotingStartTimeSeconds(uint256 _agendaID) public view returns (uint) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Agenda Id");
        return agendas[_agendaID].votingStartedTimestamp;
    }

    function getAgendaVotingEndTimeSeconds(uint256 _agendaID) public view returns (uint) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Agenda Id");
        return agendas[_agendaID].votingEndTimestamp;
    }

    function canExecuteAgenda(uint256 _agendaID) public view returns (bool) {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        return agenda.status == LibAgenda.AgendaStatus.WAITING_EXEC &&
            block.timestamp <= agenda.executableLimitTimestamp &&
            agenda.result == LibAgenda.AgendaResult.ACCEPT &&
            agenda.votingEndTimestamp <= block.timestamp &&
            agenda.executed == false;
    }
    
    function getAgendaStatus(uint256 _agendaID) public view returns (uint status) {
        require(_agendaID < agendas.length, "DAOAgendaManager: invalid agend id");
        return uint(agendas[_agendaID].status);
    }

    function totalAgendas() public view returns (uint256) {
        return agendas.length;
    }

    function getAgendaResult(uint256 _agendaID) public view returns (uint result, bool executed) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid _agendaID Id");
        return (uint(agendas[_agendaID].result), agendas[_agendaID].executed);
    }
   
    function getExecutionInfo(uint256 _agendaID)
        public
        view
        returns(
            address[] memory target,
            bytes[] memory functionBytecode
        )
    {
        LibAgenda.AgendaExecutionInfo storage agenda = executionInfos[_agendaID];
        return (
            agenda.targets,
            agenda.functionBytecodes
        );
    }

    function isVotableStatus(uint256 _agendaID) public view returns (bool) {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        return block.timestamp <= agenda.votingEndTimestamp ||
            (agenda.status == LibAgenda.AgendaStatus.NOTICE &&
                agenda.noticeEndTimestamp <= block.timestamp);
    }

    function getVotingCount(uint256 _agendaID)
        public
        view
        returns (
            uint256 countingYes,
            uint256 countingNo,
            uint256 countingAbstain
        )
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        return (
            agenda.countingYes,
            agenda.countingNo,
            agenda.countingAbstain
        );
    }

    function getAgendaTimestamps(uint256 _agendaID)
        public
        view
        returns (
            uint256 createdTimestamp,
            uint256 noticeEndTimestamp,
            uint256 votingStartedTimestamp,
            uint256 votingEndTimestamp,
            uint256 executedTimestamp
        )
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        return (
            agenda.createdTimestamp,
            agenda.noticeEndTimestamp,
            agenda.votingStartedTimestamp,
            agenda.votingEndTimestamp,
            agenda.executedTimestamp
        );
    }

    function numAgendas() public view returns (uint256) {
        return agendas.length;
    }

    function getVoters(uint256 _agendaID) public view returns (address[] memory) {
        return agendas[_agendaID].voters;
    }
}
