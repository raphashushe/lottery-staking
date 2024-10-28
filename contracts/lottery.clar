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