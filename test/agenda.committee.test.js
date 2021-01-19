const {
  defaultSender, accounts, contract, web3,
} = require('@openzeppelin/test-environment');
const {
  BN, constants, expectEvent, expectRevert, time, ether,
} = require('@openzeppelin/test-helpers');

const { padLeft, toBN } = require('web3-utils');
const { marshalString, unmarshalString } = require('./helpers/marshal');

const { createCurrency, createCurrencyRatio } = require('@makerdao/currency');
const { BigNumber } = require('bignumber.js');

const chai = require('chai');
const { expect } = chai;
chai.use(require('chai-bn')(BN)).should();

const DaoContracts = require('../utils/plasma_test_deploy.js');
const DAOCommitteeAbi = require('../build/contracts/DAOCommittee.json').abi;

// dao-contracts
const DAOVault2 = contract.fromArtifact('DAOVault2');
const DAOCommittee = contract.fromArtifact('DAOCommittee');
const DAOAgendaManager = contract.fromArtifact('DAOAgendaManager');
const CandidateFactory = contract.fromArtifact('CandidateFactory');
const DAOCommitteeProxy = contract.fromArtifact('DAOCommitteeProxy');
const Candidate = contract.fromArtifact('Candidate');

// plasma-evm-contracts
const TON = contract.fromArtifact('TON');
const WTON = contract.fromArtifact('WTON');
const DepositManager = contract.fromArtifact('DepositManager');
const SeigManager = contract.fromArtifact('SeigManager');
const CoinageFactory = contract.fromArtifact('CoinageFactory');
const Layer2Registry = contract.fromArtifact('Layer2Registry');
const AutoRefactorCoinage = contract.fromArtifact('AutoRefactorCoinage');
const PowerTON = contract.fromArtifact('PowerTON');
const DAOVault = contract.fromArtifact('DAOVault');

const EtherToken = contract.fromArtifact('EtherToken');
const EpochHandler = contract.fromArtifact('EpochHandler');
const SubmitHandler = contract.fromArtifact('SubmitHandler');
const Layer2 = contract.fromArtifact('Layer2');

let o;
process.on('exit', function () {
  console.log(o);
});

const [ candidate1, candidate2, candidate3, user1, user2, user3, user4,user5,operator1,operator2] = accounts;
const candidates = [candidate1, candidate2, candidate3];
const users = [user1, user2, user3, user4, user5];
const operators = [operator1,operator2];

const deployer = defaultSender;

const _TON = createCurrency('TON');
const _WTON = createCurrency('WTON');
const _WTON_TON = createCurrencyRatio(_WTON, _TON);

const TON_UNIT = 'wei';
const WTON_UNIT = 'ray';
const WTON_TON_RATIO = _WTON_TON('1');

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

const CANDIDATE_INFO_INDEX_CANDIDATE_CONTRACT = 0;
const CANDIDATE_INFO_INDEX_MEMBER_JOINED_TIME = 1;
const CANDIDATE_INFO_INDEX_MEMBER_INDEX = 2;
const CANDIDATE_INFO_INDEX_REWARD_PERIOD = 3;

const AGENDA_INDEX_CREATED_TIMESTAMP = 0;
const AGENDA_INDEX_NOTICE_END_TIMESTAMP = 1;
const AGENDA_INDEX_VOTING_PERIOD_IN_SECONDS = 2;
const AGENDA_INDEX_VOTING_STARTED_TIMESTAMP = 3;
const AGENDA_INDEX_VOTING_END_TIMESTAMP = 4;
const AGENDA_INDEX_EXECUTED_TIMESTAMP = 5;
const AGENDA_INDEX_COUNTING_YES = 6;
const AGENDA_INDEX_COUNTING_NO = 7;
const AGENDA_INDEX_COUNTING_ABSTAIN = 8;
const AGENDA_INDEX_REWARD = 9;
const AGENDA_INDEX_STATUS = 10;
const AGENDA_INDEX_RESULT = 11;
//const AGENDA_INDEX_VOTERS = 12;
const AGENDA_INDEX_EXECUTED = 12;

const AGENDA_STATUS_NONE = 0;
const AGENDA_STATUS_NOTICE = 1;
const AGENDA_STATUS_VOTING = 2;
const AGENDA_STATUS_WAITING_EXEC = 3;
const AGENDA_STATUS_EXECUTED = 4;
const AGENDA_STATUS_ENDED = 5;
//const AGENDA_STATUS_PENDING = 6;
//const AGENDA_STATUS_RISK = 7;

const VOTE_ABSTAIN = 0;
const VOTE_YES = 1;
const VOTE_NO = 2;

const AGENDA_RESULT_ACCEPTED = 1;
const AGENDA_RESULT_REJECTED = 2;
const AGENDA_RESULT_DISMISSED = 3;


const VOTER_INFO_ISVOTER = 0;
const VOTER_INFO_HAS_VOTED = 1;
const VOTER_INFO_VOTE = 2;

////////////////////////////////////////////////////////////////////////////////
// test settings

const WITHDRAWAL_DELAY = 10;
const SEIG_PER_BLOCK = _WTON('3.92');
const ROUND_DURATION = time.duration.minutes(5);

const TON_INITIAL_SUPPLY = _TON('50000000');
const TON_INITIAL_HOLDERS = _TON('1000000');
const TON_VAULT_AMOUNT = _WTON('10000000');

const POWERTON_SEIG_RATE = _WTON('0.1');
const DAO_SEIG_RATE = _WTON('0.5');
const PSEIG_RATE = _WTON('0.4');

const TON_MINIMUM_STAKE_AMOUNT = _TON('1000');
const TON_USER_STAKE_AMOUNT = _TON('10');
////////////////////////////////////////////////////////////////////////////////

const owner= defaultSender;
let daoVault2, committeeProxy, committee, activityRewardManager , agendaManager, candidateFactory;
let gasUsedRecords = [];
let gasUsedTotal = 0; 
let debugLog=true;
let tx  ; 
//------------------

let ton;
let wton;
let registry;
let depositManager;
let factory;
let daoVault;
let seigManager;
let powerton;

//
let noticePeriod, votingPeriod , agendaFee; 
let layer2s=[];
let DAOCommitteeAbiObj, DaoContractsDeployed ; 


describe('Test 1', function () {
  before(async function () {
    this.timeout(1000000);

    DaoContractsDeployed = new DaoContracts(); 
    DAOCommitteeAbiObj = await DaoContractsDeployed.objectMapping(DAOCommitteeAbi);
    let returnData = await DaoContractsDeployed.initializePlasmaEvmContracts(owner);
    ton = returnData.ton;
    wton = returnData.wton;
    registry = returnData.registry;
    depositManager = returnData.depositManager;
    factory = returnData.coinageFactory;
    daoVault = returnData.daoVault;
    seigManager = returnData.seigManager;
    powerton = returnData.powerton; 

    let returnData1 = await DaoContractsDeployed.initializeDaoContracts(owner);
    daoVault2 = returnData1.daoVault2;
    agendaManager = returnData1.agendaManager;
    candidateFactory = returnData1.candidateFactory;
    committee = returnData1.committee;
    committeeProxy= returnData1.committeeProxy; 

    await candidates.map(account => ton.transfer(account, TON_INITIAL_HOLDERS.toFixed(TON_UNIT), {from: deployer}));
    await users.map(account => ton.transfer(account, TON_INITIAL_HOLDERS.toFixed(TON_UNIT), {from: deployer}));  
  });
  
  async function NewSeigManager(){
    var newSeigManager = await SeigManager.new(
      ton.address,
      wton.address,
      registry.address,
      depositManager.address,
      SEIG_PER_BLOCK.toFixed(WTON_UNIT),
      factory.address
    ); 

    await newSeigManager.setPowerTON(powerton.address); 
    await newSeigManager.setDao(daoVault2.address);
    await wton.addMinter(newSeigManager.address);
    //await ton.addMinter(wton.address);
    
    /* 
    await Promise.all([
      depositManager,
      wton,
    ].map(contract => contract.setSeigManager(newSeigManager.address)));
    */ 

    newSeigManager.setPowerTONSeigRate(POWERTON_SEIG_RATE.toFixed(WTON_UNIT));
    newSeigManager.setDaoSeigRate(DAO_SEIG_RATE.toFixed(WTON_UNIT));
    newSeigManager.setPseigRate(PSEIG_RATE.toFixed(WTON_UNIT));
    await newSeigManager.setMinimumAmount(TON_MINIMUM_STAKE_AMOUNT.times(WTON_TON_RATIO).toFixed(WTON_UNIT))
    
    /* 
   console.log('layer2s[0].address', layer2s[0].address);
   console.log('seigManager', seigManager.address);
   console.log('registry.owner', await registry.owner());
   console.log('committeeProxy.address',committeeProxy.address);
    */
   
   //onlyOperatorOrSeigManager
   const _layer0 = await Layer2.at(layer2s[0].address);
   await _layer0.setSeigManager(newSeigManager.address,{from: operator1});
   const _layer1 = await Layer2.at(layer2s[1].address);
   await _layer1.setSeigManager(newSeigManager.address,{from: operator2});

   //onlyOwnerOrOperator : committeeProxy 에서 실행하거나, 
   await registry.deployCoinage(layer2s[0].address, newSeigManager.address, {from: operator1});
   await registry.deployCoinage(layer2s[1].address, newSeigManager.address, {from: operator2});

   await wton.setSeigManager(newSeigManager.address);
   await powerton.setSeigManager(newSeigManager.address);
 
   const stakeAmountTON = TON_MINIMUM_STAKE_AMOUNT.toFixed(TON_UNIT);
   const stakeAmountWTON = TON_MINIMUM_STAKE_AMOUNT.times(WTON_TON_RATIO).toFixed(WTON_UNIT);

   const coinageAddress = await newSeigManager.coinages(_layer1.address); 
   const coinage = await AutoRefactorCoinage.at(coinageAddress);
    // const stakedAmount = await coinage.balanceOf(operator2);
    // stakedAmount.should.be.bignumber.equal(stakeAmountWTON);
  
    expect(coinageAddress).to.not.equal(ZERO_ADDRESS);
    return newSeigManager;
  }

  async function addlayer2s(operator){
    let _layer2 = await DaoContractsDeployed.addOperator(operator);
    layer2s.push(_layer2);
  } 

  async function agendaVoteYesAll(agendaid){
    const agenda = await agendaManager.agendas(agendaid);  
    const noticeEndTimestamp = agenda[AGENDA_INDEX_NOTICE_END_TIMESTAMP]; 
    time.increaseTo(noticeEndTimestamp); 
    await committeeProxy.castVote(agendaid,1,' candidate1 yes ', {from: candidate1});  
    const agendaAfterStartVoting = await agendaManager.agendas(agendaid);   
    const votingEndTimestamp = agendaAfterStartVoting.votingEndTimestamp; 
    await committeeProxy.castVote(agendaid,1,' candidate2 yes ',{from:candidate2}); 

    let maxnum = await committeeProxy.maxMember();
    if(maxnum.gt(toBN("4")))  await committeeProxy.castVote(agendaid,1,' candidate3 yes ',{from:candidate3}); 
    
    time.increaseTo(votingEndTimestamp);
   
  }  
  
  async function createAgenda(_target, _functionBytecode){ 
    agendaFee = await agendaManager.createAgendaFees();

      const param = web3.eth.abi.encodeParameters(
        ["address", "uint256", "uint256", "bytes"],
        [_target, noticePeriod.toString(), votingPeriod.toString(), _functionBytecode]
      );
      // create agenda
      await ton.approveAndCall(
        committeeProxy.address,
        agendaFee,
        param,
        {from: user1}
      );
      agendaID = (await agendaManager.numAgendas()).sub(toBN("1")); 
      return agendaID;
  }

  async function executeAgenda(_target, _functionBytecode){ 
    let agendaID = await createAgenda(_target, _functionBytecode); 
    await agendaVoteYesAll(agendaID); 
    await committeeProxy.executeAgenda(agendaID);   
  }

  before(async function () { 
    this.timeout(1000000); 

    await addlayer2s(operator1);
    await addlayer2s(operator2);

    await DaoContractsDeployed.addCandidate(candidate1);
    await DaoContractsDeployed.addCandidate(candidate2);
    await DaoContractsDeployed.addCandidate(candidate3); 

    await committeeProxy.changeMember(0, {from: candidate1});
    await committeeProxy.changeMember(1, {from: candidate2});
    await committeeProxy.changeMember(2, {from: candidate3});

    noticePeriod = await agendaManager.minimunNoticePeriodSeconds();
    votingPeriod = await agendaManager.minimunVotingPeriodSeconds();
    
    
  });
  
  describe('Agenda - DAOCommittee', function () { 

    it('committeeProxy.transferOwnership to committeeProxy self ', async function () {  
      await committeeProxy.transferOwnership(committeeProxy.address);
      expect(await committeeProxy.owner()).to.equal(committeeProxy.address);
    });
    it('committeeProxy.setSeigManager', async function () {  
      let _newSeigManager = await NewSeigManager(); 
      let params = [_newSeigManager.address] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setSeigManager,params);
     
      await executeAgenda(committeeProxy.address, functionBytecode);  
      expect(await committeeProxy.seigManager()).to.equal(_newSeigManager.address); 
    });
    it('committeeProxy.setDaoVault', async function () {  
      let _daoVault2 = await DAOVault2.new(ton.address, wton.address,{from:owner});
      let params = [_daoVault2.address] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setDaoVault,params);
     
      await executeAgenda(committeeProxy.address, functionBytecode);  
      expect(await committeeProxy.daoVault()).to.equal(_daoVault2.address); 
    });
    it('committeeProxy.setLayer2Registry', async function () {  
      let _registry = await Layer2Registry.new({from:owner});
      let params = [_registry.address] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setLayer2Registry,params);
     
      await executeAgenda(committeeProxy.address, functionBytecode);  
      expect(await committeeProxy.layer2Registry()).to.equal(_registry.address); 
    });
    it('committeeProxy.setCandidateFactory', async function () {  
      let _factory =  await CandidateFactory.new({from:owner});
      let params = [_factory.address] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setCandidateFactory,params);
     
      await executeAgenda(committeeProxy.address, functionBytecode);  
      expect(await committeeProxy.candidateFactory()).to.equal(_factory.address); 
   
    });
    it('committeeProxy.registerOperatorByOwner', async function () {  
      expect(await committeeProxy.isCandidate(operator1)).to.equal(false);  
      let params = [operator1 , layer2s[0].address, 'operator1'] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.registerOperatorByOwner,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      expect(await committeeProxy.isExistCandidate(operator1)).to.equal(true); 
      
      
      params = [user2 , layer2s[1].address, 'user2'] ;
      functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.registerOperatorByOwner,params);
      let agendaID = await createAgenda(committeeProxy.address, functionBytecode); 
      await agendaVoteYesAll(agendaID);  
      await expectRevert.unspecified(committeeProxy.executeAgenda(agendaID) ); 
        
    }); 
    it('committeeProxy.setActivityRewardPerSecond', async function () {   
      let reward = await committeeProxy.activityRewardPerSecond();
      reward.should.be.bignumber.equal(toBN("1"));  
      let params = [2] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setActivityRewardPerSecond,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      reward = await committeeProxy.activityRewardPerSecond();
      reward.should.be.bignumber.equal(toBN("2"));  
       
    }); 
     
    it('committeeProxy.setMaxMember', async function () {  
      let amxnum = await committeeProxy.maxMember();
      amxnum.should.be.bignumber.equal(toBN("3"));  
      let params = [5] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setMaxMember,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      amxnum = await committeeProxy.maxMember();
      amxnum.should.be.bignumber.equal(toBN("5"));  
       
    }); 
     
    it('committeeProxy.reduceMemberSlot', async function () {  
      let amxnum = await committeeProxy.maxMember();
      amxnum.should.be.bignumber.equal(toBN("5"));  
      let params = [3] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.reduceMemberSlot,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      await executeAgenda(committeeProxy.address, functionBytecode);  
      amxnum = await committeeProxy.maxMember();
      amxnum.should.be.bignumber.equal(toBN("3"));  
    }); 

    it('committeeProxy.setAgendaStatus', async function () {  
      //setTon
      let _newton =  await TON.new({from:owner}); 
      let params = [_newton.address] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setTon,params);
      let agendaID = await createAgenda(committeeProxy.address, functionBytecode); 
      
      let agendaStatus = await agendaManager.getAgendaStatus(agendaID);
      agendaStatus.should.be.bignumber.equal(toBN("1"));
  
      params = [toBN(agendaID).toNumber(), 5, 2] ;
      functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setAgendaStatus,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      agendaStatus = await agendaManager.getAgendaStatus(agendaID); 
      agendaStatus.should.be.bignumber.equal(toBN("5"));
    });
    
    it('committeeProxy.setCreateAgendaFees', async function () {  
      let fees = await agendaManager.createAgendaFees();
      fees.should.be.bignumber.equal(toBN("100000000000000000000")); 
  
      let params = [ '200000000000000000000' ] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setCreateAgendaFees,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      fees = await agendaManager.createAgendaFees();
      fees.should.be.bignumber.equal(toBN("200000000000000000000")); 

      params = ['100000000000000000000'] ;
      functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setCreateAgendaFees,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      fees = await agendaManager.createAgendaFees();
      fees.should.be.bignumber.equal(toBN("100000000000000000000")); 

  
    });
    it('committeeProxy.setMinimunNoticePeriodSeconds', async function () {  
      let minsec = 10000;
      let min = await agendaManager.minimunNoticePeriodSeconds();
      min.should.be.bignumber.equal(toBN(minsec));  

      let params = [120] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setMinimunNoticePeriodSeconds,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      min = await agendaManager.minimunNoticePeriodSeconds();
      min.should.be.bignumber.equal(toBN("120")); 
    });

    it('committeeProxy.setMinimunVotingPeriodSeconds', async function () {  
      let minsec = 10000;
      let min = await agendaManager.minimunVotingPeriodSeconds();
      min.should.be.bignumber.equal(toBN(minsec));  

      let params = [300] ;
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setMinimunVotingPeriodSeconds,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      min = await agendaManager.minimunVotingPeriodSeconds();
      min.should.be.bignumber.equal(toBN("300")); 
    }); 

    //--
    it('committeeProxy.renounceOwnership', async function () {   
      let functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.renounceOwnership, []);
      await executeAgenda(committeeProxy.address, functionBytecode);    
      expect(await committeeProxy.owner()).to.equal(ZERO_ADDRESS); 
    });

    /* 
    it('committeeProxy.setQuorum', async function () {  
      let quorum = await agendaManager.quorum();
      quorum.numerator.should.be.bignumber.equal(toBN("2"));
      quorum.denominator.should.be.bignumber.equal(toBN("3"));
       
      params = [1, 2] ;
      functionBytecode =  web3.eth.abi.encodeFunctionCall(DAOCommitteeAbiObj.setQuorum,params);
      await executeAgenda(committeeProxy.address, functionBytecode);  
      quorum = await agendaManager.quorum();
      quorum.numerator.should.be.bignumber.equal(toBN("1"));
      quorum.denominator.should.be.bignumber.equal(toBN("2")); 
 
    });


    it('committeeProxy.transferOwnership', async function () {  
       
    });
    
    it('committeeProxy.setAgendaManager', async function () {  
       
    });
   
    it('committeeProxy.setTon', async function () {  
       
    });
    
    */
  });
 
});