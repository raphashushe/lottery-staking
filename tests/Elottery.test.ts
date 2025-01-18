import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state to simulate deployment and interactions.
let lotteryRounds: Record<string, any>;
let currentRound: number;
let tokenRegistry: Record<string, any>;
const contractOwner = 'owner';

// Reset the mock state before each test.
beforeEach(() => {
  lotteryRounds = {};
  currentRound = 0;
  tokenRegistry = {};
});

// Helper function to simulate contract methods.
function startNewRound(tier: number, sender = contractOwner) {
  if (sender !== contractOwner) return { ok: false, error: 100 }; // err-owner-only

  const nextRound = currentRound + 1;
  const roundKey = `${tier}:${nextRound}`;

  lotteryRounds[roundKey] = {
    startBlock: 0, // Simulating block height as 0 for simplicity
    endBlock: 100, // Block height + 100
    totalStaked: 0,
    winner: null,
  };

  currentRound = nextRound;
  return { ok: nextRound };
}

function registerToken(
  tokenContract: string,
  minStake: number,
  decimals: number,
  sender = contractOwner
) {
  if (sender !== contractOwner) return { ok: false, error: 100 }; // err-owner-only

  tokenRegistry[tokenContract] = {
    enabled: true,
    minStake,
    decimals,
  };

  return { ok: true };
}

// Tests for start-new-round
describe('Lottery Rounds Tests', () => {
  it('should start a new lottery round successfully', () => {
    const result = startNewRound(1);
    expect(result.ok).toBe(1); // First round
    expect(lotteryRounds['1:1']).toMatchObject({
      startBlock: 0,
      endBlock: 100,
      totalStaked: 0,
      winner: null,
    });
  });

  it('should increment the current round for the same tier', () => {
    startNewRound(1);
    const result = startNewRound(1);
    expect(result.ok).toBe(2); // Second round
    expect(lotteryRounds['1:2']).toBeDefined();
  });

  it('should reject starting a new round by a non-owner', () => {
    const result = startNewRound(1, 'user');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100); // err-owner-only
  });
});

// Tests for register-token
describe('Token Registry Tests', () => {
  it('should register a token successfully', () => {
    const result = registerToken('token_1', 100, 8);
    expect(result.ok).toBe(true);
    expect(tokenRegistry['token_1']).toMatchObject({
      enabled: true,
      minStake: 100,
      decimals: 8,
    });
  });

  it('should reject token registration by a non-owner', () => {
    const result = registerToken('token_1', 100, 8, 'user');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(100); // err-owner-only
  });

  it('should overwrite an existing token registration', () => {
    registerToken('token_1', 100, 8);
    const result = registerToken('token_1', 200, 6);
    expect(result.ok).toBe(true);
    expect(tokenRegistry['token_1']).toMatchObject({
      enabled: true,
      minStake: 200,
      decimals: 6,
    });
  });
});
