;; Decentralized Lottery with Staking
;; implements tiered lottery pools with staking rewards

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-active (err u101))
(define-constant err-already-active (err u102))
(define-constant err-insufficient-stake (err u103))
(define-constant err-pool-not-ended (err u104))
(define-constant err-pool-ended (err u105))
(define-constant err-already-entered (err u106))

;; Define pool tiers
(define-constant TIER-SMALL u0)
(define-constant TIER-MEDIUM u1)
(define-constant TIER-LARGE u2)

;; Pool data structure using a map
(define-map pools
    uint
    {
        min-stake: uint,
        total-staked: uint,
        winner-share: uint,
        staking-share: uint,
        end-block: uint,
        is-active: bool,
        winner: (optional principal)
    }
)

;; Track stakes per user per pool
(define-map stakes
    {tier: uint, user: principal}
    uint
)

;; Track participants per pool
(define-map pool-participants
    uint
    (list 50 principal)  ;; max 50 participants per pool
)

;; Getters
(define-read-only (get-pool-info (tier uint))
    (map-get? pools tier)
)

(define-read-only (get-stake (tier uint) (user principal))
    (default-to u0 
        (map-get? stakes {tier: tier, user: user}))
)

(define-read-only (get-participants (tier uint))
    (default-to (list) 
        (map-get? pool-participants tier))
)

;; Create new lottery pool
(define-public (create-lottery-pool 
        (tier uint)
        (min-stake uint)
        (duration uint)
        (winner-share uint)
        (staking-share uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (< (+ winner-share staking-share) u10000) (err u107))
        (asserts! (is-none (map-get? pools tier)) err-already-active)
        
        (map-set pools tier {
            min-stake: min-stake,
            total-staked: u0,
            winner-share: winner-share,
            staking-share: staking-share,
            end-block: (+ block-height duration),
            is-active: true,
            winner: none
        })
        (ok true)
    )
)

;; Enter lottery by staking tokens
(define-public (enter-lottery (tier uint) (amount uint))
    (let (
        (pool (unwrap! (map-get? pools tier) err-not-active))
        (current-participants (default-to (list) (map-get? pool-participants tier)))
    )
        ;; Verify pool conditions
        (asserts! (get is-active pool) err-not-active)
        (asserts! (>= amount (get min-stake pool)) err-insufficient-stake)
        (asserts! (< block-height (get end-block pool)) err-pool-ended)
        
        ;; Transfer tokens to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update pool data
        (map-set pools tier (merge pool {
            total-staked: (+ (get total-staked pool) amount)
        }))
        
        ;; Update user stake
        (map-set stakes 
            {tier: tier, user: tx-sender}
            (+ amount (get-stake tier tx-sender)))
            
        ;; Add to participants if not already in
        (if (is-none (index-of current-participants tx-sender))
            (map-set pool-participants
                tier
                (unwrap! (as-max-len? (append current-participants tx-sender) u50)
                    (err u108)))  ;; Pool full
            true)
            
        (ok true)
    )
)

;; Select winner and distribute rewards
(define-public (end-lottery (tier uint))
    (let (
        (pool (unwrap! (map-get? pools tier) err-not-active))
        (participants (unwrap! (map-get? pool-participants tier) err-not-active))
    )
        ;; Verify pool can be ended
        (asserts! (get is-active pool) err-not-active)
        (asserts! (>= block-height (get end-block pool)) err-pool-not-ended)
        (asserts! (> (len participants) u0) (err u109))
        
        ;; Select winner using VRF
        (let (
            (block-time (unwrap! (get-block-info? time (- block-height u1)) (err u111)))
            (winner-index (mod block-time (len participants)))
            (winner (unwrap! (element-at participants winner-index) (err u110)))
            (total-staked (get total-staked pool))
            (winner-amount (/ (* total-staked (get winner-share pool)) u10000))
            (staking-amount (/ (* total-staked (get staking-share pool)) u10000))
        )
            ;; Transfer winner prize
            (try! (as-contract (stx-transfer? winner-amount tx-sender winner)))
            
            ;; Distribute staking rewards
            (map-set pools tier (merge pool {
                is-active: false,
                winner: (some winner)
            }))
            
            ;; Note: In a full implementation, we'd iterate through participants
            ;; to distribute staking rewards proportionally. This is simplified.
            (ok {
                winner: winner,
                prize: winner-amount,
                staking-rewards: staking-amount
            })
        )
    )
)

;; Admin function to cancel pool in emergency
(define-public (cancel-pool (tier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((pool (unwrap! (map-get? pools tier) err-not-active)))
            (asserts! (get is-active pool) err-not-active)
            
            (map-set pools tier (merge pool {
                is-active: false,
                winner: none
            }))
            (ok true)
        )
    )
)


(define-map referrals
    principal  ;; referred user
    principal  ;; referrer
)

(define-map referral-rewards
    principal
    uint
)

(define-public (refer-user (new-user principal))
    (begin
        (asserts! (is-none (map-get? referrals new-user)) (err u200))
        (map-set referrals new-user tx-sender)
        (ok true)
    )
)

(define-public (claim-referral-rewards)
    (let (
        (rewards (default-to u0 (map-get? referral-rewards tx-sender)))
    )
        (asserts! (> rewards u0) (err u201))
        (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
        (map-set referral-rewards tx-sender u0)
        (ok rewards)
    )
)


(define-map supported-tokens
    principal  ;; token contract
    bool
)

(define-public (add-supported-token (token-contract principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set supported-tokens token-contract true)
        (ok true)
    )
)

(define-public (enter-lottery-with-token 
    (tier uint) 
    (amount uint)
    (token-contract principal))
    (begin
        (asserts! (default-to false (map-get? supported-tokens token-contract)) (err u300))
        ;; Add token transfer logic here
        (ok true)
    )
)


(define-map compound-preferences
    {tier: uint, user: principal}
    bool
)

(define-public (set-auto-compound (tier uint) (enabled bool))
    (begin
        (map-set compound-preferences
            {tier: tier, user: tx-sender}
            enabled)
        (ok true)
    )
)

(define-read-only (get-compound-setting (tier uint) (user principal))
    (default-to false 
        (map-get? compound-preferences {tier: tier, user: user}))
)


(define-data-var treasury-balance uint u0)
(define-constant treasury-fee u100) ;; 1% fee

(define-public (collect-treasury-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (fee-amount (/ (* amount treasury-fee) u10000))
        )
            (var-set treasury-balance (+ (var-get treasury-balance) fee-amount))
            (ok fee-amount)
        )
    )
)

(define-public (withdraw-treasury)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (amount (var-get treasury-balance))
        )
            (var-set treasury-balance u0)
            (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
            (ok amount)
        )
    )
)



;; Add to data structures
(define-map lottery-rounds 
    {tier: uint, round: uint}
    {
        start-block: uint,
        end-block: uint,
        total-staked: uint,
        winner: (optional principal)
    }
)

;; Add after other define-data-var declarations
(define-data-var current-roundd uint u0)


;; Add public function
(define-public (start-new-round (tier uint))
    (let (
        (current-round (var-get current-roundd))
        (next-round (+ current-round u1))
    )
        (map-set lottery-rounds 
            {tier: tier, round: next-round}
            {
                start-block: block-height,
                end-block: (+ block-height u100),
                total-staked: u0,
                winner: none
            }
        )
        (var-set current-roundd next-round)
        (ok next-round)
    )
)




;; Add at the top with other data structures
(define-map token-registry
    principal  ;; token contract
    {
        enabled: bool,
        min-stake: uint,
        decimals: uint
    }
)

(define-public (register-token 
    (token-contract principal) 
    (min-stake uint)
    (decimals uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set token-registry token-contract {
            enabled: true,
            min-stake: min-stake,
            decimals: decimals
        })
        (ok true)
    )
)


;; Add with other data structures
(define-map staking-multipliers
    {user: principal, tier: uint}
    {start-block: uint, multiplier: uint}
)

(define-public (calculate-multiplier (tier uint))
    (let (
        (user-data (default-to {start-block: block-height, multiplier: u100}
            (map-get? staking-multipliers {user: tx-sender, tier: tier})))
        (blocks-staked (- block-height (get start-block user-data)))
    )
        (if (> blocks-staked u1000)
            (map-set staking-multipliers 
                {user: tx-sender, tier: tier}
                {start-block: (get start-block user-data), multiplier: u150})
            true)
        (ok true)
    )
)


(define-map user-achievements
    principal
    {
        total-entries: uint,
        total-wins: uint,
        achievement-points: uint
    }
)

(define-public (update-achievements (user principal))
    (let (
        (current-stats (default-to {total-entries: u0, total-wins: u0, achievement-points: u0}
            (map-get? user-achievements user)))
    )
        (map-set user-achievements user
            (merge current-stats {
                total-entries: (+ (get total-entries current-stats) u1)
            }))
        (ok true)
    )
)


(define-data-var pool-scaling-factor uint u100)

(define-public (adjust-pool-size (tier uint))
    (let (
        (pool (unwrap! (map-get? pools tier) err-not-active))
        (participants-count (len (default-to (list) (map-get? pool-participants tier))))
    )
        (if (> participants-count u40)
            (var-set pool-scaling-factor u150)
            (var-set pool-scaling-factor u100))
        (ok (var-get pool-scaling-factor))
    )
)



(define-map bonus-rounds
    uint  ;; round number
    {
        active: bool,
        multiplier: uint,
        end-block: uint
    }
)

(define-public (start-bonus-round (duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set bonus-rounds (var-get current-roundd)
            {
                active: true,
                multiplier: u200,  ;; 2x rewards
                end-block: (+ block-height duration)
            })
        (ok true)
    )
)






;; contract updates


(define-public (update-lottery-pool 
        (tier uint)
        (min-stake uint)
        (duration uint)
        (winner-share uint)
        (staking-share uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((pool (unwrap! (map-get? pools tier) err-not-active)))
            (asserts! (get is-active pool) err-not-active)
            
            (map-set pools tier {
                min-stake: min-stake,
                total-staked: u0,
                winner-share: winner-share,
                staking-share: staking-share,
                end-block: (+ block-height duration),
                is-active: true,
                winner: none
            })
            (ok true)
        )
    )
)


;; Add to data structures
(define-map loyalty-points 
    principal 
    {points: uint, level: uint}
)

(define-public (award-loyalty-points (user principal) (points uint))
    (let (
        (current-points (default-to {points: u0, level: u0} 
            (map-get? loyalty-points user)))
    )
        (map-set loyalty-points user
            (merge current-points {
                points: (+ (get points current-points) points),
                level: (/ (+ (get points current-points) points) u1000)
            }))
        (ok true)
    )
)



;; Add to data structures
(define-map special-events
    uint  ;; event ID
    {
        name: (string-ascii 50),
        multiplier: uint,
        start-block: uint,
        end-block: uint
    }
)

(define-public (create-special-event 
    (name (string-ascii 50)) 
    (multiplier uint) 
    (duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set special-events (+ block-height u1) {
            name: name,
            multiplier: multiplier,
            start-block: block-height,
            end-block: (+ block-height duration)
        })
        (ok true)
    )
)



;; Add to data structures
(define-map user-streaks
    principal
    {current-streak: uint, max-streak: uint}
)

(define-public (update-streak (user principal))
    (let (
        (streak-data (default-to {current-streak: u0, max-streak: u0} 
            (map-get? user-streaks user)))
        (new-streak (+ (get current-streak streak-data) u1))
    )
        (map-set user-streaks user {
            current-streak: new-streak,
            max-streak: (if (> new-streak (get max-streak streak-data))
                new-streak
                (get max-streak streak-data))
        })
        (ok true)
    )
)



;; Add to data structures
(define-map teams
    (string-ascii 50)  ;; team name
    {
        leader: principal,
        members: (list 50 principal),
        total-staked: uint
    }
)

(define-public (create-team (team-name (string-ascii 50)))
    (begin
        (asserts! (is-none (map-get? teams team-name)) (err u400))
        (map-set teams team-name {
            leader: tx-sender,
            members: (list tx-sender),
            total-staked: u0
        })
        (ok true)
    )
)



;; Add to data structures
(define-map daily-challenges
    uint  ;; challenge ID
    {
        description: (string-ascii 100),
        reward: uint,
        participants: (list 100 principal)
    }
)

(define-public (create-daily-challenge 
    (description (string-ascii 100)) 
    (reward uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set daily-challenges block-height {
            description: description,
            reward: reward,
            participants: (list)
        })
        (ok true)
    )
)



;; Add to data structures
(define-map vip-nft-holders
    principal
    {level: uint, benefits: uint}
)

(define-public (register-vip-nft (holder principal) (nft-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set vip-nft-holders holder {
            level: u1,
            benefits: u150  ;; 1.5x multiplier
        })
        (ok true)
    )
)



;; Add to data structures
(define-data-var jackpot-pool uint u0)
(define-constant jackpot-contribution-rate u100) ;; 1%

(define-public (add-to-jackpot (amount uint))
    (begin
        (var-set jackpot-pool (+ (var-get jackpot-pool) 
            (/ (* amount jackpot-contribution-rate) u10000)))
        (ok (var-get jackpot-pool))
    )
)



;; Add to data structures
(define-map referral-tiers
    principal
    {tier: uint, total-referrals: uint}
)

(define-public (upgrade-referral-tier (referrer principal))
    (let (
        (current-data (default-to {tier: u0, total-referrals: u0} 
            (map-get? referral-tiers referrer)))
        (new-referrals (+ (get total-referrals current-data) u1))
    )
        (map-set referral-tiers referrer {
            tier: (/ new-referrals u5),  ;; Tier up every 5 referrals
            total-referrals: new-referrals
        })
        (ok true)
    )
)
;; Add to data structures
(define-map staking-duration
    {user: principal, pool-id: uint}
    {start-time: uint, multiplier: uint}
)

(define-public (calculate-time-bonus (pool-id uint))
    (let (
        (user-data (default-to {start-time: block-height, multiplier: u100}
            (map-get? staking-duration {user: tx-sender, pool-id: pool-id})))
        (time-staked (- block-height (get start-time user-data)))
    )
        (if (> time-staked u1000)
            (ok u150) ;; 1.5x multiplier after 1000 blocks
            (ok u100))
    )
)
(define-data-var progressive-jackpot uint u0)
(define-constant jackpot-rate u50) ;; 0.5% contribution

(define-public (add-to-progressive-jackpot (amount uint))
    (begin
        (var-set progressive-jackpot 
            (+ (var-get progressive-jackpot) 
               (/ (* amount jackpot-rate) u10000)))
        (ok (var-get progressive-jackpot))
    )
)
(define-map seasonal-events
    uint  ;; season id
    {
        name: (string-ascii 50),
        bonus: uint,
        start-block: uint,
        end-block: uint
    }
)

(define-public (create-season (name (string-ascii 50)) (duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set seasonal-events block-height
            {
                name: name,
                bonus: u200, ;; 2x rewards
                start-block: block-height,
                end-block: (+ block-height duration)
            })
        (ok true)
    )
)
(define-map user-milestones
    principal
    {
        games-played: uint,
        total-won: uint,
        rank: (string-ascii 20)
    }
)

(define-public (update-milestones)
    (let (
        (current (default-to {games-played: u0, total-won: u0, rank: "Beginner"}
            (map-get? user-milestones tx-sender)))
    )
        (map-set user-milestones tx-sender
            (merge current {games-played: (+ (get games-played current) u1)}))
        (ok true)
    )
)
(define-map leagues
    (string-ascii 20)  ;; league name
    {
        min-stake: uint,
        rewards-multiplier: uint,
        members: (list 100 principal)
    }
)

(define-public (join-league (league-name (string-ascii 20)))
    (let (
        (league (unwrap! (map-get? leagues league-name) (err u500)))
    )
        (asserts! (>= (get-stake TIER-SMALL tx-sender) (get min-stake league)) (err u501))
        (ok true)
    )
)
(define-map referral-system
    principal  ;; referrer
    {
        referred: (list 50 principal),
        rewards: uint
    }
)

(define-public (refer-friend (friend principal))
    (let (
        (current-refs (default-to {referred: (list), rewards: u0}
            (map-get? referral-system tx-sender)))
    )
        (map-set referral-system tx-sender
            (merge current-refs {
                referred: (unwrap! (as-max-len? 
                    (append (get referred current-refs) friend) u50) (err u502))
            }))
        (ok true)
    )
)
(define-map lucky-numbers
    {user: principal, number: uint}
    bool
)

(define-public (set-lucky-number (number uint))
    (begin
        (map-set lucky-numbers
            {user: tx-sender, number: number}
            true)
        (ok true)
    )
)
(define-map vip-status
    principal
    {
        level: uint,
        bonus-multiplier: uint,
        special-entries: uint
    }
)

(define-public (upgrade-vip-status)
    (let (
        (current-status (default-to {level: u1, bonus-multiplier: u110, special-entries: u0}
            (map-get? vip-status tx-sender)))
    )
        (map-set vip-status tx-sender
            (merge current-status {level: (+ (get level current-status) u1)}))
        (ok true)
    )
)


