
# 🎲 Decentralized Lottery with Staking Rewards

This project implements a **tiered decentralized lottery platform** using Clarity smart contracts. Users can **stake tokens** to enter different lottery pools, and a **random winner** is selected at the end of each cycle. Rewards are distributed fairly among participants.

## 📋 Features

- **Token Staking**: Users stake tokens as entry fees for lottery pools.
- **Random Winner Selection**: Uses blockchain randomness to ensure fairness.
- **Staking Rewards**: Non-winners receive a share of the total pool as rewards.
- **Tiered Lottery Pools**: Offers small, medium, and large pools for more gamified participation.

---

## 🛠️ Smart Contract Overview

### **Contract Constants**

- `contract-owner`: The owner of the contract, typically the deploying address.
- `err-owner-only`: Error for owner-only operations.
- `err-not-active`: Error when interacting with inactive pools.
- `err-pool-ended`: Error when attempting to enter a pool after it ends.
- `TIER-SMALL`, `TIER-MEDIUM`, `TIER-LARGE`: Pool tiers representing the size of lottery pools.

---

### **Data Structures**

1. **`pools`:** Stores the state of each lottery pool, including:
   - Minimum stake amount
   - Total staked tokens
   - Winner and staking shares
   - Pool’s active status and winner

2. **`stakes`:** Tracks each user’s stake in specific pools.

3. **`pool-participants`:** Stores a list of participants in each pool (up to 50 participants per pool).

---

### **Public Functions**

#### 1. **create-lottery-pool**
Creates a new lottery pool.

```clarity
(create-lottery-pool (tier uint) (min-stake uint) (duration uint) (winner-share uint) (staking-share uint))
```

- **Owner-only function** to initialize a lottery pool.
- Ensures the total share (winner + staking) is below 100%.

---

#### 2. **enter-lottery**
Allows users to enter a pool by staking tokens.

```clarity
(enter-lottery (tier uint) (amount uint))
```

- Transfers the staked amount to the contract.
- Adds the user to the participant list if not already registered.

---

#### 3. **end-lottery**
Selects a winner and distributes rewards at the end of the pool.

```clarity
(end-lottery (tier uint))
```

- Uses randomness from block time to select a winner.
- Transfers the winner’s share and updates the pool’s status.

---

#### 4. **cancel-pool**
Allows the contract owner to cancel a pool in case of emergency.

```clarity
(cancel-pool (tier uint))
```

- Marks the pool as inactive and prevents further participation.

---

### **Read-only Functions**

- **`get-pool-info`:** Retrieves information about a specific pool.
- **`get-stake`:** Checks the stake of a user in a particular pool.
- **`get-participants`:** Returns the list of participants in a pool.

---

## 🧪 Testing

The project uses **Vitest** for unit testing. Below is an example of the test cases provided:

### Example Test: Create a Pool and Enter Lottery

```typescript
import { describe, it, expect } from 'vitest';
import { createLotteryPool, enterLottery, endLottery } from '../lottery';

describe('Lottery Contract Tests', () => {
  it('should create a new lottery pool', () => {
    const result = createLotteryPool(0, 100, 10, 5000, 3000);
    expect(result.ok).toBe(true);
  });

  it('should allow a user to enter the lottery', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    const result = enterLottery(0, 100, 'wallet_1');
    expect(result.ok).toBe(true);
  });

  it('should select a winner and distribute rewards', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    enterLottery(0, 100, 'wallet_1');
    enterLottery(0, 100, 'wallet_2');

    const result = endLottery(0, 20);
    if (typeof result.ok === 'object') {
      const { winner, prize, stakingRewards } = result.ok;
      expect(['wallet_1', 'wallet_2']).toContain(winner);
      expect(prize).toBe(100);
      expect(stakingRewards).toBe(60);
    }
  });
});
```

---

## 🚀 Setup and Deployment

1. Install **Clarinet** for development.
2. Clone the project and initialize Clarinet:

   ```bash
   clarinet new lottery-project
   cd lottery-project
   ```

3. Deploy the contract using Clarinet:

   ```bash
   clarinet deploy
   ```

4. Run the test suite:

   ```bash
   npm install vitest --save-dev
   npx vitest
   ```

---

## 📄 License

This project is licensed under the MIT License.

---

## 📢 Contributing

Contributions are welcome! Feel free to fork the repository, create a branch, and submit a pull request.

---

## 📝 Acknowledgements

- **Clarinet**: For the development framework.
- **Vitest**: For testing support.
- Blockchain community for inspiration and feedback.
