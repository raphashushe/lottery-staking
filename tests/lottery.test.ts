import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state to simulate deployment and interactions.
let pools: Record<number, any>;
let stakes: Record<string, number>;
let participants: Record<number, string[]>;

beforeEach(() => {
  // Reset the state before each test.
  pools = {};
  stakes = {};
  participants = {};
});

// Helper function to simulate contract methods
function createLotteryPool(
  tier: number,
  minStake: number,
  duration: number,
  winnerShare: number,
  stakingShare: number,
  sender = 'owner'
) {
  if (sender !== 'owner') return { ok: false, error: 100 }; // err-owner-only
  if (pools[tier]) return { ok: false, error: 102 }; // err-already-active

  pools[tier] = {
    minStake,
    totalStaked: 0,
    winnerShare,
    stakingShare,
    endBlock: 10 + duration,
    isActive: true,
    participants: [],
    winner: null,
  };

  return { ok: true };
}

function enterLottery(tier: number, amount: number, sender: string) {
  const pool = pools[tier];
  if (!pool || !pool.isActive) return { ok: false, error: 101 }; // err-not-active
  if (amount < pool.minStake) return { ok: false, error: 103 }; // err-insufficient-stake
  if (participants[tier]?.includes(sender))
    return { ok: false, error: 106 }; // err-already-entered

  pool.totalStaked += amount;
  stakes[`${tier}:${sender}`] = (stakes[`${tier}:${sender}`] || 0) + amount;
  participants[tier] = [...(participants[tier] || []), sender];

  return { ok: true };
}

function endLottery(tier: number, currentBlockHeight: number) {
  const pool = pools[tier];

  // Ensure pool exists and is active
  if (!pool || !pool.isActive) return { ok: false, error: 101 }; // err-not-active
  if (currentBlockHeight < pool.endBlock) return { ok: false, error: 104 }; // err-pool-not-ended

  const poolParticipants = participants[tier] || [];

  // Check if there are participants in the pool
  if (poolParticipants.length === 0) return { ok: false, error: 109 }; // err-no-participants

  // Calculate the winner index using block height
  const winnerIndex = currentBlockHeight % poolParticipants.length;
  const winner = poolParticipants[winnerIndex];

  // Mark the pool as ended and store the winner
  pool.isActive = false;
  pool.winner = winner;

  const totalStaked = pool.totalStaked;
  const winnerAmount = Math.floor((totalStaked * pool.winnerShare) / 10000);
  const stakingAmount = Math.floor((totalStaked * pool.stakingShare) / 10000);

  return {
    ok: {
      winner,
      prize: winnerAmount,
      stakingRewards: stakingAmount,
    },
  };
}


// Tests
describe('Lottery Contract Tests', () => {
  it('should create a lottery pool successfully', () => {
    const result = createLotteryPool(0, 100, 10, 5000, 3000);
    expect(result.ok).toBe(true);
    expect(pools[0]).toMatchObject({
      minStake: 100,
      totalStaked: 0,
      winnerShare: 5000,
      stakingShare: 3000,
      isActive: true,
      winner: null,
    });
  });

  it('should allow user to enter the lottery by staking', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    const result = enterLottery(0, 100, 'wallet_1');
    expect(result.ok).toBe(true);
    expect(stakes['0:wallet_1']).toBe(100);
    expect(participants[0]).toContain('wallet_1');
  });

  it('should prevent entry with insufficient stake', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    const result = enterLottery(0, 50, 'wallet_1');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(103); // err-insufficient-stake
  });

  it('should select a winner and distribute rewards', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    enterLottery(0, 100, 'wallet_1');
    enterLottery(0, 100, 'wallet_2');
  
    const result = endLottery(0, 20); // Simulate block height of 20
  
    if (typeof result.ok === 'object' && result.ok !== null) {
      const { winner, prize, stakingRewards } = result.ok;
      expect(['wallet_1', 'wallet_2']).toContain(winner);
      expect(prize).toBe(100); // 50% of 200 STX total
      expect(stakingRewards).toBe(60); // 30% of 200 STX total
    } else {
      throw new Error(`Unexpected error: ${JSON.stringify(result)}`);
    }
  });
  
  it('should not end the lottery if the pool is still active', () => {
    createLotteryPool(0, 100, 10, 5000, 3000);
    enterLottery(0, 100, 'wallet_1');

    const result = endLottery(0, 5); // Simulate block height of 5
    expect(result.ok).toBe(false);
    expect(result.error).toBe(104); // err-pool-not-ended
  });

  it('should only allow the owner to create or cancel pools', () => {
    const result = createLotteryPool(0, 100, 10, 5000, 3000, 'wallet_2'); // Non-owner
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100); // err-owner-only
  });
});
function fail(arg0: string) {
  throw new Error('Function not implemented.');
}

