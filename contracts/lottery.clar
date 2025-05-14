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




(define-map time-based-tiers
    uint  ;; tier ID
    {
        name: (string-ascii 20),
        duration: uint,  ;; in blocks
        entry-window: uint,  ;; in blocks
        min-stake: uint,
        active: bool
    }
)

(define-data-var current-time-tier uint u0)

(define-public (create-time-tier (name (string-ascii 20)) (duration uint) (entry-window uint) (min-stake uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (tier-id (+ (var-get current-time-tier) u1))
        )
            (var-set current-time-tier tier-id)
            (map-set time-based-tiers tier-id {
                name: name,
                duration: duration,
                entry-window: entry-window,
                min-stake: min-stake,
                active: true
            })
            (ok tier-id)
        )
    )
)

(define-public (enter-time-tier (tier-id uint) (amount uint))
    (let (
        (tier (unwrap! (map-get? time-based-tiers tier-id) (err u700)))
    )
        (asserts! (get active tier) (err u701))
        (asserts! (>= amount (get min-stake tier)) err-insufficient-stake)
        
        ;; Transfer tokens to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Record entry
        (map-set time-tier-entries 
            {tier: tier-id, user: tx-sender}
            {amount: amount, entry-block: block-height})
            
        (ok true)
    )
)

(define-map time-tier-entries
    {tier: uint, user: principal}
    {amount: uint, entry-block: uint}
)

(define-public (resolve-time-tier (tier-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (tier (unwrap! (map-get? time-based-tiers tier-id) (err u700)))
        )
            (map-set time-based-tiers tier-id (merge tier {active: false}))
            (ok true)
        )
    )
)


(define-map nft-discount-config
    principal  ;; NFT contract
    {
        discount-percent: uint,  ;; out of 10000
        enabled: bool
    }
)

(define-map user-nft-discounts
    {user: principal, tier: uint}
    {
        discount-applied: bool,
        discount-amount: uint
    }
)

(define-public (configure-nft-discount (nft-contract principal) (discount-percent uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= discount-percent u5000) (err u800))  ;; Max 50% discount
        (map-set nft-discount-config nft-contract {
            discount-percent: discount-percent,
            enabled: true
        })
        (ok true)
    )
)

(define-public (apply-nft-discount (tier uint) (nft-contract principal) (nft-id uint))
    (let (
        (discount-config (unwrap! (map-get? nft-discount-config nft-contract) (err u801)))
    )
        (asserts! (get enabled discount-config) (err u802))
        
        ;; In a real implementation, verify NFT ownership here
        ;; For simplicity, we're just applying the discount
        
        (map-set user-nft-discounts 
            {user: tx-sender, tier: tier}
            {
                discount-applied: true,
                discount-amount: (get discount-percent discount-config)
            })
        (ok (get discount-percent discount-config))
    )
)

(define-read-only (get-entry-cost-with-discount (tier uint) (base-amount uint))
    (let (
        (discount (default-to {discount-applied: false, discount-amount: u0}
            (map-get? user-nft-discounts {user: tx-sender, tier: tier})))
    )
        (if (get discount-applied discount)
            (- base-amount (/ (* base-amount (get discount-amount discount)) u10000))
            base-amount)
    )
)


(define-map subscriptions
    principal
    {
        active: bool,
        tier: uint,
        amount-per-round: uint,
        last-entry-round: uint
    }
)

(define-data-var current-subscription-round uint u0)

(define-public (subscribe-to-lottery (tier uint) (amount-per-round uint))
    (begin
        (asserts! (> amount-per-round u0) (err u900))
        (map-set subscriptions tx-sender {
            active: true,
            tier: tier,
            amount-per-round: amount-per-round,
            last-entry-round: (var-get current-subscription-round)
        })
        (ok true)
    )
)

(define-public (cancel-subscription)
    (begin
        (map-set subscriptions tx-sender 
            (merge (default-to {active: false, tier: u0, amount-per-round: u0, last-entry-round: u0}
                (map-get? subscriptions tx-sender))
                {active: false}))
        (ok true)
    )
)

(define-public (process-subscription-round)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set current-subscription-round (+ (var-get current-subscription-round) u1))
        (ok (var-get current-subscription-round))
    )
)

(define-public (enter-with-subscription)
    (let (
        (sub (unwrap! (map-get? subscriptions tx-sender) (err u901)))
    )
        (asserts! (get active sub) (err u902))
        (asserts! (< (get last-entry-round sub) (var-get current-subscription-round)) (err u903))
        
        ;; Transfer tokens to contract
        (try! (stx-transfer? (get amount-per-round sub) tx-sender (as-contract tx-sender)))
        
        ;; Update subscription
        (map-set subscriptions tx-sender 
            (merge sub {last-entry-round: (var-get current-subscription-round)}))
            
        ;; Enter the lottery
        (try! (enter-lottery (get tier sub) (get amount-per-round sub)))
        
        (ok true)
    )
)


(define-map leaderboard-entries
    {user: principal, season: uint}
    {
        wins: uint,
        entries: uint,
        total-staked: uint,
        points: uint
    }
)

(define-data-var current-season uint u1)

(define-public (start-new-season)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set current-season (+ (var-get current-season) u1))
        (ok (var-get current-season))
    )
)

(define-public (record-leaderboard-entry (user principal) (amount uint))
    (let (
        (current-entry (default-to {wins: u0, entries: u0, total-staked: u0, points: u0}
            (map-get? leaderboard-entries {user: user, season: (var-get current-season)})))
    )
        (map-set leaderboard-entries 
            {user: user, season: (var-get current-season)}
            {
                wins: (get wins current-entry),
                entries: (+ (get entries current-entry) u1),
                total-staked: (+ (get total-staked current-entry) amount),
                points: (+ (get points current-entry) (calculate-points amount))
            })
        (ok true)
    )
)

(define-public (record-leaderboard-win (user principal))
    (let (
        (current-entry (default-to {wins: u0, entries: u0, total-staked: u0, points: u0}
            (map-get? leaderboard-entries {user: user, season: (var-get current-season)})))
    )
        (map-set leaderboard-entries 
            {user: user, season: (var-get current-season)}
            (merge current-entry {
                wins: (+ (get wins current-entry) u1),
                points: (+ (get points current-entry) u1000)
            }))
        (ok true)
    )
)

(define-read-only (get-leaderboard-entry (user principal))
    (default-to {wins: u0, entries: u0, total-staked: u0, points: u0}
        (map-get? leaderboard-entries {user: user, season: (var-get current-season)}))
)

(define-private (calculate-points (amount uint))
    (/ amount u1000000)  ;; 1 point per 1 STX
)


(define-map prize-pool-multipliers
    uint  ;; tier
    {
        base-multiplier: uint,
        oracle-based: bool,
        min-multiplier: uint,
        max-multiplier: uint
    }
)

(define-data-var oracle-value uint u100)  ;; Default 1x multiplier (100%)

(define-public (set-prize-pool-config (tier uint) (base-multiplier uint) (oracle-based bool) (min-multiplier uint) (max-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set prize-pool-multipliers tier {
            base-multiplier: base-multiplier,
            oracle-based: oracle-based,
            min-multiplier: min-multiplier,
            max-multiplier: max-multiplier
        })
        (ok true)
    )
)

(define-public (update-oracle-value (new-value uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set oracle-value new-value)
        (ok (var-get oracle-value))
    )
)

(define-read-only (get-current-prize-multiplier (tier uint))
    (let (
        (config (default-to {base-multiplier: u100, oracle-based: false, min-multiplier: u50, max-multiplier: u200}
            (map-get? prize-pool-multipliers tier)))
    )
        (if (get oracle-based config)
            (clamp 
                (get min-multiplier config)
                (get max-multiplier config)
                (/ (* (get base-multiplier config) (var-get oracle-value)) u100))
            (get base-multiplier config))
    )
)

(define-private (clamp (min uint) (max uint) (value uint))
    (if (< value min)
        min
        (if (> value max)
            max
            value))
)




(define-map tier-scaling
    uint
    {
        base-prize: uint,
        participant-threshold: uint,
        scaling-factor: uint,
        last-updated: uint
    }
)

(define-data-var scaling-enabled bool true)

(define-public (configure-tier-scaling (tier uint) (base uint) (threshold uint) (factor uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set tier-scaling tier {
            base-prize: base,
            participant-threshold: threshold,
            scaling-factor: factor,
            last-updated: block-height
        })
        (ok true)
    )
)

(define-public (adjust-tier-prizes (tier uint))
    (let (
        (config (unwrap! (map-get? tier-scaling tier) (err u1000)))
        (pool (unwrap! (map-get? pools tier) (err u1001)))
        (participants (len (default-to (list) (map-get? pool-participants tier))))
    )
        (if (and (var-get scaling-enabled) (> participants (get participant-threshold config)))
            (map-set pools tier (merge pool {
                winner-share: (+ (get winner-share pool) (get scaling-factor config))
            }))
            true)
        (ok true)
    )
)


(define-map token-pools
    {pool-id: uint, token: principal}
    {
        weight: uint,
        total-staked: uint,
        enabled: bool
    }
)

(define-map user-token-stakes
    {pool-id: uint, token: principal, user: principal}
    uint
)

(define-public (add-token-to-pool (pool-id uint) (token principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set token-pools 
            {pool-id: pool-id, token: token}
            {weight: weight, total-staked: u0, enabled: true})
        (ok true)
    )
)

(define-public (stake-token (pool-id uint) (token principal) (amount uint))
    (let (
        (pool (unwrap! (map-get? token-pools {pool-id: pool-id, token: token}) (err u2000)))
    )
        (asserts! (get enabled pool) (err u2001))
        ;; TODO: Add token transfer logic
        ;; (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender)))
        (map-set token-pools 
            {pool-id: pool-id, token: token}
            (merge pool {total-staked: (+ (get total-staked pool) amount)}))
        (map-set user-token-stakes
            {pool-id: pool-id, token: token, user: tx-sender}
            (+ amount (default-to u0 (map-get? user-token-stakes 
                {pool-id: pool-id, token: token, user: tx-sender}))))
        (ok true)
    )
)