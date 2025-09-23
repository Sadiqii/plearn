# P2P Learning Platform Smart Contract

A Clarity smart contract for a decentralized quiz platform with STX token rewards.

## Core Features

* **Quiz Management**
  * Create quizzes with titles and rewards
  * Auto or manual verification options
  * Quiz activation/deactivation controls

* **User Interactions**
  * Submit answers to quizzes
  * Claim STX rewards after verification
  * View quiz information and participation status

* **Admin System**
  * Multi-admin support
  * Admin addition/removal capabilities
  * Verified answer management

## Technical Details

* **Storage**
  * Maps for quizzes, completions, contributors, and statistics
  * Structured data storage for quiz and user information
  * Verification tracking system

* **Security**
  * Authorization checks
  * Input validation
  * Balance verification
  * Duplicate submission prevention
  * List size limitations (100 verified users max)

* **Token Integration**
  * STX token reward system
  * Minimum reward: 1 STX
  * Maximum reward: 100,000 STX
  * Contract balance management

## Read-Only Functions

* Get quiz details
* Check user status
* View quiz statistics
* Verify admin status
* Check contract balance
* Get verified users list

## Public Functions

* Initialize contract
* Submit quiz answers
* Verify answers
* Claim rewards
* Fund contract
* Manage admins
* Create/deactivate quizzes

This contract runs on the Stacks blockchain and uses Clarity smart contract language.
