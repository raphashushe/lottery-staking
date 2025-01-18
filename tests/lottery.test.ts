import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state to simulate deployment and interactions.
let pools: Record<number, any>;
let stakes: Record<string, number>;
let participants: Record<number, string[]>;
let referrals: Record<string, string>;
let referralRewards: Record<string, number>;
let supportedTokens: Record<string, boolean>;
let compoundPreferences: Record<string, boolean>;
let treasuryBalance: number;

beforeEach(() => {
  // Reset the state before each test.
  pools = {};
  stakes = {};
  participants = {};
  referrals = {};
  referralRewards = {};
  supportedTokens = {};
  compoundPreferences = {};
  treasuryBalance = 0;
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

function referUser(newUser: string, referrer: string) {
  if (referrals[newUser]) return { ok: false, error: 200 };
  referrals[newUser] = referrer;
  return { ok: true };
}

function addSupportedToken(tokenContract: string, sender: string) {
  if (sender !== 'owner') return { ok: false, error: 100 };
  supportedTokens[tokenContract] = true;
  return { ok: true };
}

function setAutoCompound(tier: number, user: string, enabled: boolean) {
  compoundPreferences[`${tier}:${user}`] = enabled;
  return { ok: true };
}

function collectTreasuryFees(amount: number, sender: string) {
  if (sender !== 'owner') return { ok: false, error: 100 };
  const fee = Math.floor((amount * 100) / 10000); // 1% fee
  treasuryBalance += fee;
  return { ok: { feeAmount: fee } };
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


describe('Referral System Tests', () => {
  it('should successfully refer a new user', () => {
    const result = referUser('new_user', 'referrer');
    expect(result.ok).toBe(true);
    expect(referrals['new_user']).toBe('referrer');
  });

  it('should prevent referring an existing user', () => {
    referUser('new_user', 'referrer');
    const result = referUser('new_user', 'another_referrer');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(200);
  });
});

describe('Token Registry Tests', () => {
  it('should add supported token by owner', () => {
    const result = addSupportedToken('token_contract', 'owner');
    expect(result.ok).toBe(true);
    expect(supportedTokens['token_contract']).toBe(true);
  });

  it('should reject token addition by non-owner', () => {
    const result = addSupportedToken('token_contract', 'user');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100);
  });
});

describe('Auto-Compound Tests', () => {
  it('should set auto-compound preference', () => {
    const result = setAutoCompound(0, 'user1', true);
    expect(result.ok).toBe(true);
    expect(compoundPreferences['0:user1']).toBe(true);
  });

  it('should update existing auto-compound preference', () => {
    setAutoCompound(0, 'user1', true);
    const result = setAutoCompound(0, 'user1', false);
    expect(result.ok).toBe(true);
    expect(compoundPreferences['0:user1']).toBe(false);
  });
});

describe('Treasury Tests', () => {
  it('should collect fees correctly', () => {
    const result = collectTreasuryFees(10000, 'owner');
    expect(result.ok).toMatchObject({ feeAmount: 100 });
    expect(treasuryBalance).toBe(100);
  });

  it('should reject fee collection by non-owner', () => {
    const result = collectTreasuryFees(10000, 'user');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100);
  });
});