pragma solidity ^0.8.0;

contract FinancialLease {
    
    struct Asset {
        address payable owner;
        uint256 id;
        uint256 value;
        uint256 lifespan;
        Rental rental;
    }
    
    struct Rental {
        uint256 cyclePeriodicity;
        uint256 fineRate;
        uint256 terminationFine;
    }
    
    uint256 public countPayedCycles;
    uint256 public countCurrentCycle; 
    uint256 public interestRate;
    uint256 public leaseDuration;
    uint256 public leaseStartime; //private
    uint256 public rental;
    uint256 public residualValue;
    uint256 public monthlyInstallment;
    uint256 public monthlyInsurance;
    uint256[] public cycles;
    uint256 public currentTime; //private
    uint256 public endCycle; //private
    uint256 public timeLeftToPayResidualValue;
    
    event NewOwner(address newOwner, string text);
    event AssetDestroyed(address iCompany, string text);
    
    enum State { CREATED, SIGNED, VALID, TERMINATED }
    State public state;
    
    Asset public my_asset;
    Rental public my_rental;
    
    address payable public smartContract;
    address payable public lessor;
    address payable public insuranceCompany; 
    address payable public lessee;
    
    constructor() {
        smartContract = payable(address(this));
        lessor = payable(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
        insuranceCompany = payable(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db);
        lessee = payable(0x617F2E2fD72FD9D5503197092aC168c91465E7f2);
        interestRate = 0;
        leaseDuration = 0;
        leaseStartime = 0;
        monthlyInstallment =  0;
        monthlyInsurance = 0;
        rental = 0;
        residualValue = 0;
        countPayedCycles = 0;
        countCurrentCycle = 0;
        currentTime = 0;
        endCycle = 0;
        timeLeftToPayResidualValue = 0;
    }
    
    modifier inState(State s) {
        require(state == s, "Not in the proper state");
        _;
    }
    
    receive() external payable {}
    fallback() external payable {}
    
    function setAssetParameters(uint256 id, uint256 value, uint256 lifespan, uint256 cyclePeriodicity, uint256 fineRate, uint256 terminationFine) public {
        require(payable(msg.sender) == lessor);
        my_rental = Rental(cyclePeriodicity, fineRate, terminationFine);
        my_asset = Asset(payable(msg.sender), id, value, lifespan, my_rental);
        monthlyInstallment = my_asset.value / my_asset.lifespan;
        state = State.CREATED;
    }
    
    function signContractInsuranceCompany(uint256 inteRate) inState(State.CREATED) public {
        require(payable(msg.sender) == insuranceCompany);
        interestRate = inteRate;
        state = State.SIGNED;
    }
    
    function signContractLessee(uint256 duration) inState(State.SIGNED) public {
        require(payable(msg.sender) == lessee);
        leaseDuration = duration;
        monthlyInsurance = ((my_asset.value * interestRate) / 100) / leaseDuration;
        residualValue = my_asset.value - (monthlyInstallment * leaseDuration);
        state = State.VALID;
        if(leaseStartime == 0){
            leaseStartime = block.timestamp;
            rental = monthlyInstallment + monthlyInsurance;
            countPayedCycles = 0;
            countCurrentCycle = 1;
        }
        uint256 temp;
        temp = leaseStartime;
        for (uint256 i=0; i < leaseDuration; i++) {
            temp = temp + my_asset.rental.cyclePeriodicity; 
            cycles.push(temp); 
        } 
    }
    
    function getSmartContractBalance() public returns (uint256) {
        require(payable(msg.sender) == lessor);
        return smartContract.balance;
    }
    
    function payRental() inState(State.VALID) public payable {
        require(payable(msg.sender) == lessee);
        require(msg.value >= rental, "The value should be higher or equal to the rental!");
        currentTime = block.timestamp;
        countCurrentCycle = checkCurrentCycle(currentTime);
        endCycle = leaseStartime + (countCurrentCycle * my_asset.rental.cyclePeriodicity );
        uint256 fine = monthlyInsurance + (monthlyInstallment + ((monthlyInstallment * my_asset.rental.fineRate) / 100));
        if (countPayedCycles + 2 == countCurrentCycle && countPayedCycles < leaseDuration && msg.value >= fine) {
            smartContract.transfer(fine); 
            insuranceCompany.transfer(monthlyInsurance);
            countPayedCycles += 1;
            if(msg.value > fine){
                payable(msg.sender).transfer(msg.value-fine);
            }
        } else if(countPayedCycles + 2 == countCurrentCycle && countPayedCycles < leaseDuration && msg.value < fine) {
            revert("Is necessary to pay the fine rate");   
        } else if(countCurrentCycle - countPayedCycles >= 3) {
            state = State.TERMINATED;
        } else if(currentTime <= endCycle && countPayedCycles + 1 < leaseDuration && countPayedCycles + 1 == countCurrentCycle){
            smartContract.transfer(monthlyInstallment);
            insuranceCompany.transfer(monthlyInsurance);
            countPayedCycles += 1;
            if(msg.value > rental){
                payable(msg.sender).transfer(msg.value-rental);
            }
        } else if (countPayedCycles + 1 == leaseDuration) {
            smartContract.transfer(monthlyInstallment);
            insuranceCompany.transfer(monthlyInsurance);
            countPayedCycles += 1;
            timeLeftToPayResidualValue = block.timestamp + 1 minutes;
            if(msg.value > rental){
                payable(msg.sender).transfer(msg.value-rental);
            }
        } else if (countPayedCycles == leaseDuration) {
            revert("All rentals are payed. Choose to pay or not to pay the remaining residual value!");
        } else {
            revert();
        }
    }
    
    function checkCurrentCycle(uint256 cTime) private returns (uint256) {
        for (uint256 i=0; i < leaseDuration; i++) {
            if(cTime <= cycles[0]){
                countCurrentCycle = 1;
            } else if(i > 0 && cycles[i-1] < cTime && cTime <= cycles[i]){
                countCurrentCycle = i+1;
            } 
        }
        return countCurrentCycle;
    }
    
    function withdrawMoney(uint256 quantityDesired) public payable {
        require(msg.sender == lessor);
        if(quantityDesired <= smartContract.balance){
            lessor.transfer(quantityDesired);
        } else {
            revert("Not enough money!");
        }
    }
    
    function payAdvanceAmortizations() inState(State.VALID) public payable {
        require(msg.sender == lessee);
        if(residualValue - msg.value >= 0) {
            residualValue -= msg.value;
            smartContract.transfer(msg.value);
        } else {
            revert("Insert correct amount of amortization!");
        }
    }
    
    function finishLeasing() inState(State.VALID) public payable {
        require(payable(msg.sender) == lessee);
        currentTime = block.timestamp;
        countCurrentCycle = checkCurrentCycle(currentTime);
        if(countCurrentCycle == 1 && msg.value == 0){
            state = State.TERMINATED;
        } else if (countCurrentCycle == 1 && msg.value > 0)  {
            revert("No fine needed to be paid, value should be 0");
        } else if (msg.value == my_rental.terminationFine) {
            smartContract.transfer(my_rental.terminationFine);
            state = State.TERMINATED;
        } else {
            revert("Value should be equal to termination fine!");
        } 
    }
    
    function liquidateAsset() inState(State.VALID) public payable {
        require(payable(msg.sender) == lessee);
        require(msg.value == monthlyInstallment * (leaseDuration - countPayedCycles), "Message value should be equal to the sum of the remaining monthly instalements!");
        currentTime = block.timestamp;
        countCurrentCycle = checkCurrentCycle(currentTime);
        if(countPayedCycles < leaseDuration){
            smartContract.transfer(monthlyInstallment * (leaseDuration - countPayedCycles));
            countPayedCycles = leaseDuration;
            timeLeftToPayResidualValue = block.timestamp + 1 minutes;
        } else {
            revert("All rentals are payed. Choose to pay or not to pay the remaining residual value!");
        }
    }
    
    function paysWholeValue (bool paysRemainingValue) inState(State.VALID) public payable {
        require(payable(msg.sender) == lessee);
        if(block.timestamp <= timeLeftToPayResidualValue){
            if(countPayedCycles == leaseDuration && paysRemainingValue && msg.value == residualValue) {
                smartContract.transfer(residualValue);
                my_asset.owner = lessee;
                emit NewOwner(lessee, "Lessee bought the whole asset and now it is the new owner!");
                state = State.TERMINATED;
            } else if(countPayedCycles == leaseDuration && !paysRemainingValue) {
                state = State.TERMINATED;
            } else if(0 <= msg.value && msg.value != residualValue && paysRemainingValue){
                revert("The payment should be equal to the residual value!");
            } else {
                revert("Must pay all rentals!");
            }
        } else {
            state = State.TERMINATED;
        }
    }
    
    function destroyAsset() inState(State.VALID) public payable {
        require(payable(msg.sender) == insuranceCompany);
        require(msg.value == my_asset.value, "Message value should be equal to asset value!");
        smartContract.transfer(my_asset.value);
        delete my_asset;
        emit AssetDestroyed(insuranceCompany, "The Asset has been destroyed by the Insurance Company!");
        state = State.TERMINATED;
    }
} 
