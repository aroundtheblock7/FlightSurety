# FlightSurety

FlightSurety is a sample application project for Udacity's Blockchain course.

## Requirements

    Node v10.16.0
    Truffle 5.4.17
    Web3 1.5.1
    Ganache- Please connect to Ganache UI on port 7545 for this project!

## Install

This repository contains Smart Contract code in Solidity (using Truffle), tests (also using Truffle), dApp scaffolding (using HTML, CSS and JS) and server app scaffolding.

To install, download or clone the repo, then:

`npm install`

`truffle compile`

## Develop Client

To run truffle tests:

`truffle test ./test/flightSurety.js`

`truffle test ./test/oracles.js`

To use the dapp:

`truffle migrate` (PLEASE USE GANACHE UI ON PORT 7545)

`npm run dapp`

To view dapp:

`http://localhost:8000`

## Develop Server

`npm run server`
`truffle test ./test/oracles.js`

## Deploy

To build dapp for prod:
`npm run dapp:prod`

Deploy the contents of the ./dapp folder
