pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./FlightSuretyData.sol";

contract FlightSuretyApp {
    using SafeMath for uint256;

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;
    uint256 private constant CREDIT_MULTIPLIER = 15;

    address private contractOwner;
    FlightSuretyData dataContract;

    event RegisteredAirline(address airlineID);

    constructor(address _dataContract) public {
        contractOwner = msg.sender;
        dataContract = FlightSuretyData(_dataContract);
    }

    //Fallback function for funding smart contract.
    function() external payable {}

    //Modifier that calls the isOperational function & requires the state var "operational" (bool) to be true in the data contract
    //This is used on all state changing functions to pause the contract in the event there is an issue that needs to be fixed
    modifier requireIsOperational() {
        // Modify to call data contract's status
        require(
            dataContract.isOperational(),
            "Contract is currently not operational"
        );
        _;
    }

    //Modifier that requires the "ContractOwner" account to be the function caller
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireAirlineSubmittedFunding() {
        require(
            dataContract.hasFundingBeenSubmitted(msg.sender),
            "Requires funding has been submitted by registering airline"
        );
        _;
    }

    function isOperational() public view returns (bool) {
        return dataContract.isOperational();
    }

    //Add an airline to the registration
    //must get list of addresses in a array before deciding how to handle registration with "if else" statement
    //if airline is one of first 4 being registered than it can be added by calling addToRegisteredAirlines in the data contract
    //if airline is 5th airline than it must be voted for. This is done by calling voteForAirline function
    //if airline has recieved > 50% of votes, it can be registered by calling addToRegisteredAirline function
    function registerAirline(address airline)
        public
        requireIsOperational
        requireAirlineSubmittedFunding
    {
        require(
            dataContract.hasAirlineBeenAdded(airline),
            "Requires airline has been added"
        );

        address[] memory registeredAirlines = (
            dataContract.getRegisteredAirlines()
        );

        if (registeredAirlines.length < 5) {
            require(
                msg.sender == registeredAirlines[0],
                "Requires first airline to register first 4 airlines"
            );
            dataContract.addToRegisteredAirlines(airline);
            emit RegisteredAirline(airline);
        } else {
            require(
                dataContract.hasAirlineBeenRegistered(msg.sender),
                "Requires registering airline is registered"
            );
            require(
                !dataContract.hasAirlineVotedFor(msg.sender, airline),
                "Requires registering airline hasn't already voted"
            );

            uint256 votes = dataContract.voteForAirline(msg.sender, airline);
            if (
                SafeMath.div(
                    SafeMath.mul(votes, 100),
                    registeredAirlines.length
                ) >= 50
            ) {
                dataContract.addToRegisteredAirlines(airline);
                emit RegisteredAirline(airline);
            }
        }
    }

    //Airline submits funding.
    //Call the "setFundingSubmitted" function in the data contract which flips the fundingSubmitted property to true
    function submitAirlineRegistrationFund()
        external
        payable
        requireIsOperational
    {
        require(
            !dataContract.hasFundingBeenSubmitted(msg.sender),
            "Requires funding wasn't already provided"
        );
        require(
            msg.value == 10 ether,
            "Requires registration funds be 10 ether"
        );
        address(dataContract).transfer(msg.value);
        dataContract.setFundingSubmitted(msg.sender);
    }

    //Register a future flight for insuring.
    function registerFlight(
        address airlineID,
        string flight,
        uint256 timestamp
    ) external requireIsOperational {
        dataContract.addToRegisteredFlights(airlineID, flight, timestamp);
    }

    function fetchFlightStatus(
        address airlineID,
        string flight,
        uint256 timestamp
    ) external requireIsOperational {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(
            abi.encodePacked(index, airlineID, flight, timestamp)
        );
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, airlineID, flight, timestamp);
    }

    //Called after oracle has updated flight status
    function processFlightStatus(
        address airlineID,
        string flight,
        uint8 statusCode
    ) internal requireIsOperational {
        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            dataContract.creditInsurees(airlineID, flight, CREDIT_MULTIPLIER);
        }
    }

    function buyInsurance(address airlineID, string flight)
        external
        payable
        requireIsOperational
    {
        require(
            msg.value <= 1 ether,
            "Requires insured amount of less than 1 ether"
        );
        dataContract.addToInsurancePolicy(
            airlineID,
            flight,
            msg.sender,
            msg.value
        );
        address(dataContract).transfer(msg.value);
    }

    function withdrawCredits() external requireIsOperational {
        dataContract.withdrawCreditsForInsuree(msg.sender);
    }

    // ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;
        bool isOpen;
        mapping(uint8 => address[]) responses;
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );

    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3]) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, statusCode);
        }
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }
}
