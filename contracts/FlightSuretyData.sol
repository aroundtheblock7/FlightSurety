pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false
    address[] private registeredAirlines; //array to store registered airlines

    struct Airline {
        address airlineID;
        string airlineName;
        bool isRegistered;
        bool fundingSubmitted;
        uint256 registrationVotes;
    }

    mapping(address => Airline) private airlines; //mapping of Airline struct

    struct Flight {
        string flight;
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airlineID;
    }

    //Mapping for flights, map with bytes32 with data/hash here, not address.
    mapping(bytes32 => Flight) private flights;

    struct Insurance {
        address insuree;
        uint256 amountInsuredFor;
    }

    //maps hash created in function addToInsurancePolicy to array of policies
    //when buyInsurance function is called in the app contract it calls addToInsurancePolicy in data contract
    mapping(bytes32 => Insurance[]) private policies;

    //Mapping for authorizedCallers
    //To be used in a modifier to make sure authorizedCaller can only call certain functions
    //Must also create a function to add authorizedCallers and deauthorize callers
    mapping(address => bool) private authorizedCallers;

    //mapping from "voteHash" to bool to keep track whethere or not arline has been voted for
    //"voteHash" created after airline is voted for in function voteForAirline and flips bool to true
    //function "voteForAirline" takes airlineVoterID & airlineVoteeID addresses to create voteHash
    mapping(bytes32 => bool) private airlineRegistrationVotes;

    //maps addresses to credit amount received
    //used in the "creditInsurees" function and again in "withdrawCreditsForInsuree" function
    mapping(address => uint256) private credits;

    event AddedAirline(address airlineID);

    constructor() public {
        contractOwner = msg.sender;
        authorizedCallers[msg.sender] = true;
    }

    //Modifier that requires the "ContractOwner" account to be the function caller
    modifier requireContractOwner() {
        require(
            msg.sender == contractOwner,
            "Requires caller is contract owner"
        );
        _;
    }

    //Modifier that calls the "isOperational" function that retuns state bool var "operational" true
    //This is can be used to pause the contract in the event there is an issue that needs to be fixed
    modifier requireIsOperational() {
        require(isOperational(), "Requires contract is operational");
        _;
    }

    modifier requireAuthorizedCaller() {
        require(
            authorizedCallers[msg.sender] == true,
            "Requires caller is authorized to call this function"
        );
        _;
    }

    //Only contractOwner can set "authorized callers"
    function authorizeCaller(address caller) external requireContractOwner {
        authorizedCallers[caller] = true;
    }

    //Only contractOwner can deauthorize a user.
    function deauthorizeCaller(address caller) external requireContractOwner {
        authorizedCallers[caller] = false;
    }

    //Gets operating status of contract and returns A bool that is the current operating status
    function isOperational()
        public
        view
        requireAuthorizedCaller
        returns (bool)
    {
        return operational;
    }

    //Sets contract operations on/off. When operational mode is disabled, all write transactions except for this one will fail
    //Only contractOwner can call this
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    //Add a new airline to Airline struct mapping. Still must be "regsitered" after this.
    function addAirline(address airlineID, string airlineName)
        external
        requireAuthorizedCaller
        requireIsOperational
    {
        airlines[airlineID] = Airline({
            airlineID: airlineID,
            airlineName: airlineName,
            isRegistered: false,
            fundingSubmitted: false,
            registrationVotes: 0
        });

        emit AddedAirline(airlineID);
    }

    //return statement here checkcs airlines mapping is equal to airlineID, if so returns true
    function hasAirlineBeenAdded(address airlineID)
        external
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (bool)
    {
        return airlines[airlineID].airlineID == airlineID;
    }

    //Airline must be added with addAirline function (add struct) before it can be registered here.
    //Flip isRegistered bool to true and push airlineID address to registeredAirline array here.
    //This function is called from the "registerAirline" function in the App contract
    function addToRegisteredAirlines(address airlineID)
        external
        requireAuthorizedCaller
        requireIsOperational
    {
        airlines[airlineID].isRegistered = true;
        registeredAirlines.push(airlineID);
    }

    //This function is called from the "registerAirline" function in the App contract as a require to check it has been registered
    function hasAirlineBeenRegistered(address airlineID)
        external
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (bool)
    {
        return airlines[airlineID].isRegistered;
    }

    //Returns registeredAirlines array of addresses
    function getRegisteredAirlines()
        external
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (address[] memory)
    {
        return registeredAirlines;
    }

    //airlineVoterID address is msg.sender calling function, airlineVoteeID is address of airline being voted for
    //airlineVoterID and airlineVoteeID are the inputs used to create bytes32 "voteHash" variable
    //flip the airlineRegistrationVotes bool to true and add +1 to .registrationVotes struct property
    //this function is called in the App contract in the registerAirline function if consensus of 50%+ is reached
    function voteForAirline(address airlineVoterID, address airlineVoteeID)
        external
        requireAuthorizedCaller
        requireIsOperational
        returns (uint256)
    {
        bytes32 voteHash = keccak256(
            abi.encodePacked(airlineVoterID, airlineVoteeID)
        );
        airlineRegistrationVotes[voteHash] = true;
        airlines[airlineVoteeID].registrationVotes += 1;

        return airlines[airlineVoteeID].registrationVotes;
    }

    //We still need to define "bytes32 voteHash" here before we return "airlineRegistration" mapping bool (true).
    function hasAirlineVotedFor(address airlineVoterID, address airlineVoteeID)
        external
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (bool)
    {
        bytes32 voteHash = keccak256(
            abi.encodePacked(airlineVoterID, airlineVoteeID)
        );
        return airlineRegistrationVotes[voteHash] == true;
    }

    //flips the airlines mapping struct property "fundingSubmitted" to true
    //this function is called in the App contract's "submitAirlineRegistrationFund" function where 1 wei must be paid
    //this just flips the flag to true but the transfer/payment is handled in the app contract
    function setFundingSubmitted(address airlineID)
        external
        requireAuthorizedCaller
        requireIsOperational
    {
        airlines[airlineID].fundingSubmitted = true;
    }

    //returns mapping struct property "fundingSubmitted" bool true
    function hasFundingBeenSubmitted(address airlineID)
        external
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (bool)
    {
        return airlines[airlineID].fundingSubmitted == true;
    }

    //Here we use the flights mapping that calls the getFlightKey function (creates hash) and assigns to flight struct
    //This is called in the "registerFlight" function in the App contract
    function addToRegisteredFlights(
        address airlineID,
        string flight,
        uint256 timestamp
    ) external requireAuthorizedCaller requireIsOperational {
        flights[getFlightKey(airlineID, flight, timestamp)] = Flight({
            isRegistered: true,
            statusCode: 0, // STATUS_CODE_LATE_AIRLINE
            updatedTimestamp: timestamp,
            airlineID: airlineID,
            flight: flight
        });
    }

    //Every insurance policy is assocatied with a specific airline and flight so both need to be taken as inputs
    //as well as the the 2 properties in the Insruance Struct
    //Here we use "policies" mapping which takes bytes32 hash we are creating and maps to Insurance[] sturct array.
    //Because policies maps to Insurance array, we need to push to the struct Array (not just assign)
    //function here is called in the buyInsurance function in the App contract
    //buyInsurance in the App contract handles the payment/transfer of funds and calls this function
    //which assigns the "policies" mapping with Insurance struct
    function addToInsurancePolicy(
        address airlineID,
        string flight,
        address _insuree,
        uint256 amountToInsureFor
    ) external requireAuthorizedCaller requireIsOperational {
        policies[keccak256(abi.encodePacked(airlineID, flight))].push(
            Insurance({insuree: _insuree, amountInsuredFor: amountToInsureFor})
        );
    }

    //This only credits the insuree's account, they must us withdrawCreditsForInsuree function to withdraw/transfer funds
    //Customers may have multiple insurance policies for diff airlines/flights so function input takes "airlineID" & "flight"
    //Must create a new array "policiesToCredit" to store values than loop through policies mapping.
    //This function is called in the processFlightStatus function in the App contract for flights that are late status code!
    function creditInsurees(
        address airlineID,
        string flight,
        uint256 creditMultiplier
    ) external requireAuthorizedCaller requireIsOperational {
        bytes32 policyKey = keccak256(abi.encodePacked(airlineID, flight));
        Insurance[] memory policiesToCredit = policies[policyKey];

        uint256 currentCredits;
        for (uint256 i = 0; i < policiesToCredit.length; i++) {
            currentCredits = credits[policiesToCredit[i].insuree];
            // Calculate payout with multiplier and add to existing credits
            uint256 creditsPayout = (
                policiesToCredit[i].amountInsuredFor.mul(creditMultiplier).div(
                    10
                )
            );
            credits[policiesToCredit[i].insuree] = currentCredits.add(
                creditsPayout
            );
        }

        delete policies[policyKey];
    }

    //Allows the customer/insuree to withdraw funds that have been credited already in the creditInsuree function
    //Uses the credits mapping. Maps from insuree address to uint256 "credits"
    function withdrawCreditsForInsuree(address insuree)
        external
        requireAuthorizedCaller
        requireIsOperational
    {
        uint256 creditsAvailable = credits[insuree];
        require(creditsAvailable > 0, "Requires credits are available");
        credits[insuree] = 0;
        insuree.transfer(creditsAvailable);
    }

    function getFlightKey(
        address airlineID,
        string memory flight,
        uint256 timestamp
    )
        internal
        view
        requireAuthorizedCaller
        requireIsOperational
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(airlineID, flight, timestamp));
    }

    //Fallback function for funding smart contract.
    function() external payable {}
}
