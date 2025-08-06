;; Liquidity Pool Management for Lottery Platform
;; Allows users to provide liquidity and earn yield while supporting lottery prize pools

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u5000))
(define-constant err-pool-not-found (err u5001))
(define-constant err-insufficient-balance (err u5002))
(define-constant err-invalid-amount (err u5003))
(define-constant err-pool-locked (err u5004))
(define-constant err-insufficient-liquidity (err u5005))
(define-constant err-cooldown-active (err u5006))
(define-constant err-invalid-apr (err u5007))
(define-constant err-pool-inactive (err u5008))
(define-constant err-max-pools-reached (err u5009))
(define-constant err-invalid-duration (err u5010))

;; Pool constants
(define-constant MAX-POOLS u10)
(define-constant MIN-LIQUIDITY u1000000) ;; 1 STX minimum
(define-constant YIELD-PRECISION u10000) ;; For APR calculations

;; Pool data structure
(define-map liquidity-pools
    uint ;; pool-id
    {
        name: (string-ascii 50),
        total-liquidity: uint,
        annual-yield-rate: uint, ;; basis points (10000 = 100%)
        lottery-allocation: uint, ;; percentage allocated to lottery prizes
        lock-duration: uint, ;; blocks
        created-block: uint,
        is-active: bool,
        admin-fee: uint ;; basis points
    }
)

;; User liquidity positions
(define-map user-positions
    {pool-id: uint, user: principal}
    {
        amount: uint,
        deposit-block: uint,
        last-claim-block: uint,
        accumulated-yield: uint,
        lock-until-block: uint
    }
)

;; Pool statistics
(define-map pool-stats
    uint ;; pool-id
    {
        total-providers: uint,
        total-yield-distributed: uint,
        lottery-contributions: uint,
        last-yield-calculation: uint
    }
)

;; User global stats
(define-map user-liquidity-stats
    principal
    {
        total-pools-joined: uint,
        total-liquidity-provided: uint,
        total-yield-earned: uint,
        active-positions: uint
    }
)

;; Pool yield distribution tracking
(define-map yield-snapshots
    {pool-id: uint, block-height: uint}
    {
        yield-per-token: uint,
        total-distributed: uint
    }
)

;; Emergency withdrawal tracking
(define-map emergency-withdrawals
    {pool-id: uint, user: principal}
    {
        requested-block: uint,
        amount: uint,
        processed: bool
    }
)

;; Data variables
(define-data-var next-pool-id uint u1)
(define-data-var platform-fee uint u300) ;; 3% platform fee
(define-data-var emergency-cooldown uint u144) ;; ~24 hours in blocks
(define-data-var yield-distribution-frequency uint u1008) ;; ~1 week in blocks

;; Create new liquidity pool
(define-public (create-liquidity-pool 
    (name (string-ascii 50))
    (annual-yield-rate uint) 
    (lottery-allocation uint)
    (lock-duration uint)
    (admin-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= annual-yield-rate u5000) err-invalid-apr) ;; Max 50% APR
        (asserts! (<= lottery-allocation u5000) err-invalid-amount) ;; Max 50% to lottery
        (asserts! (>= lock-duration u144) err-invalid-duration) ;; Min 24 hours lock
        (asserts! (<= admin-fee u1000) err-invalid-amount) ;; Max 10% admin fee
        (asserts! (< (var-get next-pool-id) MAX-POOLS) err-max-pools-reached)
        
        (let (
            (pool-id (var-get next-pool-id))
        )
            (map-set liquidity-pools pool-id {
                name: name,
                total-liquidity: u0,
                annual-yield-rate: annual-yield-rate,
                lottery-allocation: lottery-allocation,
                lock-duration: lock-duration,
                created-block: stacks-block-height,
                is-active: true,
                admin-fee: admin-fee
            })
            
            (map-set pool-stats pool-id {
                total-providers: u0,
                total-yield-distributed: u0,
                lottery-contributions: u0,
                last-yield-calculation: stacks-block-height
            })
            
            (var-set next-pool-id (+ pool-id u1))
            (ok pool-id)
        )
    )
)

;; Provide liquidity to a pool
(define-public (provide-liquidity (pool-id uint) (amount uint))
    (let (
        (pool (unwrap! (map-get? liquidity-pools pool-id) err-pool-not-found))
        (current-position (default-to 
            {amount: u0, deposit-block: u0, last-claim-block: u0, accumulated-yield: u0, lock-until-block: u0}
            (map-get? user-positions {pool-id: pool-id, user: tx-sender})))
        (stats (unwrap! (map-get? pool-stats pool-id) err-pool-not-found))
        (user-stats (default-to 
            {total-pools-joined: u0, total-liquidity-provided: u0, total-yield-earned: u0, active-positions: u0}
            (map-get? user-liquidity-stats tx-sender)))
    )
        (asserts! (get is-active pool) err-pool-inactive)
        (asserts! (>= amount MIN-LIQUIDITY) err-invalid-amount)
        
        ;; Transfer tokens to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Calculate new lock period
        (let (
            (new-lock-block (+ stacks-block-height (get lock-duration pool)))
            (is-new-provider (is-eq (get amount current-position) u0))
        )
            ;; Update pool data
            (map-set liquidity-pools pool-id 
                (merge pool {total-liquidity: (+ (get total-liquidity pool) amount)}))
            
            ;; Update user position
            (map-set user-positions {pool-id: pool-id, user: tx-sender} {
                amount: (+ (get amount current-position) amount),
                deposit-block: stacks-block-height,
                last-claim-block: stacks-block-height,
                accumulated-yield: (get accumulated-yield current-position),
                lock-until-block: new-lock-block
            })
            
            ;; Update pool stats
            (map-set pool-stats pool-id 
                (merge stats {
                    total-providers: (if is-new-provider 
                        (+ (get total-providers stats) u1) 
                        (get total-providers stats))
                }))
            
            ;; Update user global stats
            (map-set user-liquidity-stats tx-sender {
                total-pools-joined: (if is-new-provider 
                    (+ (get total-pools-joined user-stats) u1)
                    (get total-pools-joined user-stats)),
                total-liquidity-provided: (+ (get total-liquidity-provided user-stats) amount),
                total-yield-earned: (get total-yield-earned user-stats),
                active-positions: (if is-new-provider 
                    (+ (get active-positions user-stats) u1)
                    (get active-positions user-stats))
            })
            
            (ok true)
        )
    )
)

;; Calculate pending yield for a user
(define-read-only (calculate-pending-yield (pool-id uint) (user principal))
    (let (
        (pool (unwrap! (map-get? liquidity-pools pool-id) (err u0)))
        (position (unwrap! (map-get? user-positions {pool-id: pool-id, user: user}) (err u0)))
        (blocks-since-last-claim (- stacks-block-height (get last-claim-block position)))
        (annual-blocks u52560) ;; Approximate blocks per year
        (yield-rate (get annual-yield-rate pool))
        (user-amount (get amount position))
    )
        (if (> blocks-since-last-claim u0)
            (ok (/ (* (* user-amount yield-rate) blocks-since-last-claim) 
                   (* annual-blocks YIELD-PRECISION)))
            (ok u0))
    )
)

;; Claim accumulated yield
(define-public (claim-yield (pool-id uint))
    (let (
        (pool (unwrap! (map-get? liquidity-pools pool-id) err-pool-not-found))
        (position (unwrap! (map-get? user-positions {pool-id: pool-id, user: tx-sender}) err-insufficient-balance))
        (pending-yield (unwrap! (calculate-pending-yield pool-id tx-sender) err-invalid-amount))
        (platform-fee-amount (/ (* pending-yield (var-get platform-fee)) YIELD-PRECISION))
        (user-yield (- pending-yield platform-fee-amount))
        (stats (unwrap! (map-get? pool-stats pool-id) err-pool-not-found))
        (user-stats (default-to 
            {total-pools-joined: u0, total-liquidity-provided: u0, total-yield-earned: u0, active-positions: u0}
            (map-get? user-liquidity-stats tx-sender)))
    )
        (asserts! (get is-active pool) err-pool-inactive)
        (asserts! (> pending-yield u0) err-invalid-amount)
        
        ;; Transfer yield to user
        (try! (as-contract (stx-transfer? user-yield tx-sender tx-sender)))
        
        ;; Update position
        (map-set user-positions {pool-id: pool-id, user: tx-sender}
            (merge position {
                last-claim-block: stacks-block-height,
                accumulated-yield: (+ (get accumulated-yield position) user-yield)
            }))
        
        ;; Update pool stats
        (map-set pool-stats pool-id 
            (merge stats {total-yield-distributed: (+ (get total-yield-distributed stats) user-yield)}))
        
        ;; Update user global stats
        (map-set user-liquidity-stats tx-sender
            (merge user-stats {total-yield-earned: (+ (get total-yield-earned user-stats) user-yield)}))
        
        (ok user-yield)
    )
)

;; Withdraw liquidity (after lock period)
(define-public (withdraw-liquidity (pool-id uint) (amount uint))
    (let (
        (pool (unwrap! (map-get? liquidity-pools pool-id) err-pool-not-found))
        (position (unwrap! (map-get? user-positions {pool-id: pool-id, user: tx-sender}) err-insufficient-balance))
        (stats (unwrap! (map-get? pool-stats pool-id) err-pool-not-found))
        (user-stats (default-to 
            {total-pools-joined: u0, total-liquidity-provided: u0, total-yield-earned: u0, active-positions: u0}
            (map-get? user-liquidity-stats tx-sender)))
    )
        (asserts! (>= stacks-block-height (get lock-until-block position)) err-pool-locked)
        (asserts! (<= amount (get amount position)) err-insufficient-balance)
        (asserts! (> amount u0) err-invalid-amount)
        
        ;; Claim any pending yield first
        (try! (claim-yield pool-id))
        
        ;; Transfer liquidity back to user
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        
        ;; Update position
        (let (
            (new-amount (- (get amount position) amount))
            (is-full-withdrawal (is-eq new-amount u0))
        )
            (if is-full-withdrawal
                (map-delete user-positions {pool-id: pool-id, user: tx-sender})
                (map-set user-positions {pool-id: pool-id, user: tx-sender}
                    (merge position {amount: new-amount})))
            
            ;; Update pool liquidity
            (map-set liquidity-pools pool-id 
                (merge pool {total-liquidity: (- (get total-liquidity pool) amount)}))
            
            ;; Update pool stats if full withdrawal
            (if is-full-withdrawal
                (map-set pool-stats pool-id 
                    (merge stats {total-providers: (- (get total-providers stats) u1)}))
                true)
            
            ;; Update user global stats if full withdrawal
            (if is-full-withdrawal
                (map-set user-liquidity-stats tx-sender
                    (merge user-stats {active-positions: (- (get active-positions user-stats) u1)}))
                true)
            
            (ok amount)
        )
    )
)

;; Emergency withdrawal (with penalty)
(define-public (emergency-withdraw (pool-id uint))
    (let (
        (position (unwrap! (map-get? user-positions {pool-id: pool-id, user: tx-sender}) err-insufficient-balance))
        (emergency-record (default-to 
            {requested-block: u0, amount: u0, processed: false}
            (map-get? emergency-withdrawals {pool-id: pool-id, user: tx-sender})))
        (amount (get amount position))
        (penalty (/ (* amount u1000) YIELD-PRECISION)) ;; 10% penalty
        (withdrawal-amount (- amount penalty))
    )
        (asserts! (> amount u0) err-insufficient-balance)
        (asserts! (not (get processed emergency-record)) err-invalid-amount)
        
        ;; Check if cooldown period has passed if previously requested
        (if (> (get requested-block emergency-record) u0)
            (asserts! (>= (- stacks-block-height (get requested-block emergency-record)) 
                         (var-get emergency-cooldown)) err-cooldown-active)
            true)
        
        ;; Record emergency withdrawal
        (map-set emergency-withdrawals {pool-id: pool-id, user: tx-sender} {
            requested-block: stacks-block-height,
            amount: withdrawal-amount,
            processed: true
        })
        
        ;; Transfer reduced amount to user
        (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
        
        ;; Remove user position
        (map-delete user-positions {pool-id: pool-id, user: tx-sender})
        
        (ok withdrawal-amount)
    )
)

;; Allocate funds to lottery prize pool
(define-public (allocate-to-lottery (pool-id uint) (lottery-tier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (pool (unwrap! (map-get? liquidity-pools pool-id) err-pool-not-found))
            (stats (unwrap! (map-get? pool-stats pool-id) err-pool-not-found))
            (allocation-amount (/ (* (get total-liquidity pool) (get lottery-allocation pool)) YIELD-PRECISION))
        )
            (asserts! (get is-active pool) err-pool-inactive)
            (asserts! (> allocation-amount u0) err-insufficient-liquidity)
            
            ;; Transfer to lottery contract
            (try! (as-contract (contract-call? .lottery enter-lottery lottery-tier allocation-amount)))
            
            ;; Update pool stats
            (map-set pool-stats pool-id 
                (merge stats {lottery-contributions: (+ (get lottery-contributions stats) allocation-amount)}))
            
            (ok allocation-amount)
        )
    )
)

;; Admin functions
(define-public (toggle-pool (pool-id uint) (active bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (pool (unwrap! (map-get? liquidity-pools pool-id) err-pool-not-found))
        )
            (map-set liquidity-pools pool-id (merge pool {is-active: active}))
            (ok active)
        )
    )
)

(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-amount) ;; Max 10%
        (var-set platform-fee new-fee)
        (ok new-fee)
    )
)

(define-public (update-emergency-cooldown (new-cooldown uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set emergency-cooldown new-cooldown)
        (ok new-cooldown)
    )
)

;; Read-only functions
(define-read-only (get-pool-info (pool-id uint))
    (map-get? liquidity-pools pool-id)
)

(define-read-only (get-user-position (pool-id uint) (user principal))
    (map-get? user-positions {pool-id: pool-id, user: user})
)

(define-read-only (get-pool-stats (pool-id uint))
    (map-get? pool-stats pool-id)
)

(define-read-only (get-user-stats (user principal))
    (map-get? user-liquidity-stats user)
)

(define-read-only (get-platform-config)
    {
        next-pool-id: (var-get next-pool-id),
        platform-fee: (var-get platform-fee),
        emergency-cooldown: (var-get emergency-cooldown),
        yield-distribution-frequency: (var-get yield-distribution-frequency)
    }
)

(define-read-only (calculate-pool-apy (pool-id uint))
    (let (
        (pool (unwrap! (map-get? liquidity-pools pool-id) (err u0)))
        (stats (unwrap! (map-get? pool-stats pool-id) (err u0)))
        (base-apy (get annual-yield-rate pool))
        (lottery-bonus u50) ;; Additional 0.5% for lottery participation
    )
        (ok (+ base-apy lottery-bonus))
    )
)

