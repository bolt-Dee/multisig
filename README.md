# STX MultiSig Wallet

A secure multi-signature wallet implementation for Stacks blockchain, written in Clarity v3.

## Features

- ✅ Multi-signature STX transfers
- 🔒 Configurable signature threshold
- 👥 Support for up to 20 authorized owners
- 📝 Transaction proposal and approval workflow
- ⏸️ Emergency pause functionality
- 🔍 Comprehensive read-only functions for dApp integration

## Contract Overview

This contract implements a multi-signature wallet that requires a configurable number of owner signatures to execute STX transfers. It provides a secure way to manage shared funds with multiple stakeholders.

### Key Functions

```clarity
(initialize (owners-list-param (list 20 principal)) (req-threshold uint))
(propose (to principal) (amount uint))
(approve (id uint))
(revoke (id uint))
(execute (id uint))
(cancel (id uint))
```

## Security Features

- Authorization checks on all sensitive operations
- Prevention of double-execution attacks
- Signature validation before transfers
- Built-in pause mechanism for emergency control
- Owner-only access control

## Getting Started

1. Deploy the contract to the Stacks blockchain
2. Initialize with owner list and threshold:
```clarity
(contract-call? .multisig initialize (list tx-sender) u1)
```

3. Propose a transaction:
```clarity
(contract-call? .multisig propose 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u1000)
```

4. Approve and execute:
```clarity
(contract-call? .multisig approve u1)
(contract-call? .multisig execute u1)
```

## Error Codes

- `ERR-UNAUTHORIZED (u100)`: Caller not authorized
- `ERR-BAD-ARGS (u101)`: Invalid arguments
- `ERR-NOT-FOUND (u102)`: Transaction not found
- `ERR-ALREADY (u103)`: Action already performed
- `ERR-INSUFFICIENT (u104)`: Insufficient approvals
- `ERR-PAUSED (u105)`: Contract is paused

## Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js & npm (for testing)

### Testing

```bash
clarinet test
```

Built with ❤️ for the Stacks ecosystem
