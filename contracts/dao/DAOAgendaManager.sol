// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { SafeMath } from "../../node_modules/@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from  "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDAOCommittee } from "../interfaces/IDAOCommittee.sol";
import { LibAgenda } from "../lib/Agenda.sol";
import "../../node_modules/@openzeppelin/contracts/access/Ownable.sol";

contract DAOAgendaManager is Ownable {
    using SafeMath for uint256;
    using LibAgenda for *;

    enum VoteChoice { ABSTAIN, YES, NO, MAX }

    struct Ratio {
        uint256 numerator;
        uint256 denominator;
    }
    
    address public ton;
    address public activityRewardManager;
    IDAOCommittee public committee;
    
    //uint256 public numAgendas;
    //uint256 public numExecAgendas;
    
    uint256 public createAgendaFees; // 아젠다생성비용
    
    uint256 public minimunNoticePeriodSeconds;
    uint256 public minimunVotingPeriodSeconds;
    
    LibAgenda.Agenda[] public agendas;
    mapping(uint256 => mapping(address => LibAgenda.Voter)) public voterInfos;
    mapping(uint256 => LibAgenda.AgendaExecutionInfo) public executionInfos;
    
    Ratio public quorum;
    
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
    
    constructor(address _ton/*, address _activityRewardManager*/) {
        minimunNoticePeriodSeconds = 60 * 60 * 24 * 15; //  15 days , on seconds
        minimunVotingPeriodSeconds = 60 * 60 * 24 * 2; //  2 days , on seconds
        
        createAgendaFees = 0;
        quorum = Ratio(1, 2);
        ton = _ton;
        //numAgendas = 0;
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

    function setCommittee(address _committee) public onlyOwner {
        require(_committee != address(0), "DAOAgendaManager: address is zero");
        committee = IDAOCommittee(_committee);
    }

    function setStatus(uint256 _agendaID, uint _status) public onlyOwner {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Proposal Id");

        emit AgendaStatusChanged(_agendaID, uint(agendas[_agendaID].status), _status);
        agendas[_agendaID].status = getStatus(_status);
    }

    function setCreateAgendaFees(uint256 _createAgendaFees) public onlyOwner {
        createAgendaFees = _createAgendaFees;
    }

    function setMinimunNoticePeriodSeconds(uint256 _minimunNoticePeriodSeconds) public onlyOwner {
        minimunNoticePeriodSeconds = _minimunNoticePeriodSeconds;
    }

    function setMinimunVotingPeriodSeconds(uint256 _minimunVotingPeriodSeconds) public onlyOwner {
        minimunVotingPeriodSeconds = _minimunVotingPeriodSeconds;
    }
      
    function setActivityRewardManager(address _man) public onlyOwner {
        require(_man != address(0), "DAOAgendaManager: ActivityRewardManager is zero");
        activityRewardManager = _man;
    }

    function setQuorum(uint256 quorumNumerator, uint256 quorumDenominator) public onlyOwner {
        require(quorumNumerator > 0 && quorumDenominator > 0 && quorumNumerator < quorumDenominator, "DAOAgendaManager: invalid quorum");
        quorum = Ratio(quorumNumerator,quorumDenominator);
    }
    
    function hasVoted(uint256 _agendaID, address _user) public view returns (bool) {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Proposal Id");
        return voterInfos[_agendaID][_user].hasVoted;
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
            agenda.result == LibAgenda.AgendaResult.ACCEPT &&
            agenda.executed == false;

        /*require(agenda.status == uint(LibAgenda.AgendaStatus.WAITING_EXEC), "DAOAgendaManager: agenda status must be WAITING_EXEC.");
        //require(agenda.votingEndTimestamp < block.timestamp, "DAOAgendaManager: for this agenda, the voting time is not expired");
        require(agenda.result == LibAgenda.AgendaResult.ACCEPT, "DAOAgendaManager: for this agenda, not accept");
        require(agenda.executed == false, "DAOAgendaManager: already executed agenda");*/
    }
    
    /*function detailedAgenda(uint256 _agendaID)
        public
        view
        returns (
            address[2] memory creator,
            uint[8] memory datas,
            uint256[3] memory counting,
            uint256 fees,
            bool executed,
            bytes memory functionBytecode,
            address[] memory voters
        )
    {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Agenda Id");
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        uint[8] memory args1 = [
            uint(agenda.status),
            uint(agenda.result),
            //uint(agenda.group),
            agenda.createdTimestamp,
            agenda.noticeEndTimestamp,
            agenda.votingStartedTimestamp,
            agenda.votingEndTimestamp,
            agenda.executedTimestamp
        ];
        
        return (
            [agenda.creator, agenda.target],
            args1,
            agenda.counting,
            agenda.fees,
            agenda.executed,
            agenda.functionBytecode,
            agenda.voters
        );
    }*/

    /*function detailedAgendaVoteInfo(uint256 _agendaID, address voter)
        public
        view
        returns (
            bool hasVoted,
            uint256 vote,
            string memory comment
        )
    {
        require(_agendaID < agendas.length, "DAOAgendaManager: Not a valid Agenda Id");

        if (voterInfos[_agendaID][voter].hasVoted) {
            return (voterInfos[_agendaID][voter].hasVoted, voterInfos[_agendaID][voter].vote, voterInfos[_agendaID][voter].comment);
        } else {
            return (false, 0, '');
        }
    }*/
    
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
   
    function newAgenda(
        address _target,
        uint256 _noticePeriodSeconds,
        uint256 _votingPeriodSeconds,
        uint256 _reward,
        bytes calldata _functionBytecode
    )
        onlyOwner
        public
        returns (uint256 agendaID)
    {
        require(_noticePeriodSeconds >= minimunNoticePeriodSeconds, "DAOAgendaManager: minimunNoticePeriod is short");
        agendaID = agendas.length;
         
        LibAgenda.Agenda memory p;
        p.status = LibAgenda.AgendaStatus.NOTICE;
        p.result = LibAgenda.AgendaResult.PENDING;
        p.executed = false;
        p.createdTimestamp = block.timestamp;
        p.noticeEndTimestamp = block.timestamp + 60 * 60 * _noticePeriodSeconds;
        p.votingPeriodInSeconds = _votingPeriodSeconds;
        p.votingStartedTimestamp = 0;
        p.votingEndTimestamp = 0;
        p.executedTimestamp = 0;
        p.reward = _reward;
        
        agendas.push(p);

        LibAgenda.AgendaExecutionInfo storage executionInfo = executionInfos[agendaID];
        executionInfo.target = _target;
        executionInfo.functionBytecode = _functionBytecode;

        //numAgendas = agendas.length;
        //agendaID = numAgendas.sub(1);
    }

    function startVoting(uint256 _agendaID) public {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        require(
            agenda.status == LibAgenda.AgendaStatus.NOTICE,
            "DAOAgendaManager: invalid status"
        );
        require(
            agenda.noticeEndTimestamp <= block.timestamp,
            "DAOAgendaManager: can not start voting yet"
        );

        agenda.votingStartedTimestamp = block.timestamp;
        agenda.votingEndTimestamp = block.timestamp.add(agenda.votingPeriodInSeconds);
        agenda.status = LibAgenda.AgendaStatus.VOTING;

        uint256 memberCount = committee.maxMember();
        for (uint256 i = 0; i < memberCount; i++) {
            address voter = committee.members(i);
            agenda.voters.push(voter);
            voterInfos[_agendaID][voter].isVoter = true;
        }

        emit AgendaStatusChanged(_agendaID, uint(LibAgenda.AgendaStatus.NOTICE), uint(LibAgenda.AgendaStatus.VOTING));
    }
    
    function isVoter(uint256 _agendaID, address _user) public view returns (bool) {
        require(_user != address(0), "DAOAgendaManager: user address is zero");
        return voterInfos[_agendaID][_user].isVoter;
    }
    
    function castVote(
        uint256 _agendaID,
        address _voter,
        uint _vote
    )
        public
        onlyOwner
        returns (bool)
    {
        require(_vote < uint(VoteChoice.MAX), "DAOCommittee: invalid vote");
        require(isVoter(_agendaID, _voter), "DAOCommittee: not a voter");
        require(!hasVoted(_agendaID, _voter), "DAOCommittee: already voted");

        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        require(
            agenda.status == LibAgenda.AgendaStatus.VOTING,
            "DAOAgendaManager: status is not voting."
        );
        require(
            isVoter(_agendaID, _voter),
            "you are not a committee member on this agenda."
        );
        require(
            !hasVoted(_agendaID, _voter),
            "voter already voted on this proposal"
        );
        require(
            agendas[_agendaID].votingStartedTimestamp <= block.timestamp &&
            block.timestamp <= agendas[_agendaID].votingEndTimestamp,
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
        
        return true;
    }
    
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

    function checkAndEndVoting(uint256 _agendaID) internal {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];

        require(
            agenda.status == LibAgenda.AgendaStatus.VOTING,
            "DAOAgendaManager: status is not voting."
        );
    }

    /*function agendaStepNext(uint256 _agendaID) public onlyOwner {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        uint256 prevStatus = agenda.status;
        uint256 prevResult = agenda.result;

        if (agenda.status == LibAgenda.AgendaStatus.NOTICE) {
        } else if (agenda.status == LibAgenda.AgendaStatus.VOTING) {
            // The agenda is on voting process
            if (agenda.result == LibAgenda.AgendaResult.ACCEPT) {
                // The agenda is accepted
                agenda.status = LibAgenda.AgendaStatus.WAITING_EXEC;
            } else if (
                agenda.result == LibAgenda.AgendaResult.REJECT ||
                agenda.result == LibAgenda.AgendaResult.DISMISS
            ) {
                // The agenda is rejected
                agenda.status = LibAgenda.AgendaStatus.ENDED;
            } else if (
                agenda.result == LibAgenda.AgendaResult.PENDING &&
                agenda.votingEndTimestamp < block.timestamp
            ) {
                // The agenda is dismissed
                agenda.status = LibAgenda.AgendaStatus.ENDED;
                agenda.result = LibAgenda.AgendaResult.DISMISS;
            }
        } else if (agenda.status == LibAgenda.AgendaStatus.WAITING_EXEC) {
        } else if (agenda.status == LibAgenda.AgendaStatus.VOTING) {
        } else if (agenda.status == LibAgenda.AgendaStatus.VOTING) {
        } else if (agenda.status == LibAgenda.AgendaStatus.VOTING) {
        }

        emit AgendaStepNext(
            _agendaID,
            prevStatus,
            prevResult,
            agenda.status,
            agenda.result
        );
    }*/

    function setResult(uint256 _agendaID, LibAgenda.AgendaResult _result)
        public
        onlyOwner
    {
        LibAgenda.Agenda storage agenda = agendas[_agendaID];
        agenda.result = _result;

        emit AgendaResultChanged(_agendaID, uint(_result));
    }
     
    function getExecutionInfo(uint256 _agendaID)
        public
        view
        returns(
            address target,
            bytes memory functionBytecode
        )
    {
        LibAgenda.AgendaExecutionInfo storage agenda = executionInfos[_agendaID];
        return (
            agenda.target,
            agenda.functionBytecode
        );
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
