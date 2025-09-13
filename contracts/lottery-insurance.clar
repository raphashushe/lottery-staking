;; Lottery Insurance System
;; Provides risk protection for lottery participants through insurance policies

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u6000))
(define-constant err-insufficient-funds (err u6001))
(define-constant err-policy-not-found (err u6002))
(define-constant err-policy-expired (err u6003))
(define-constant err-already-claimed (err u6004))
(define-constant err-invalid-amount (err u6005))
(define-constant err-pool-insufficient (err u6006))
(define-constant err-invalid-tier (err u6007))
(define-constant err-claim-too-early (err u6008))

;; Insurance pool and settings
(define-data-var insurance-pool uint u0)
(define-data-var base-premium-rate uint u500) ;; 5% base premium rate
(define-data-var payout-percentage uint u7000) ;; 70% payout on claim
(define-data-var min-policy-amount uint u100000) ;; 0.1 STX minimum
(define-data-var claim-delay-blocks uint u10) ;; Minimum blocks before claim

;; Policy data structure
(define-map insurance-policies
    {user: principal, policy-id: uint}
    {
        lottery-tier: uint,
        insured-amount: uint,
        premium-paid: uint,
        purchase-block: uint,
        expiry-block: uint,
        is-active: bool,
        claimed: bool,
        lottery-entry-block: uint
    }
)

;; User policy tracking
(define-map user-policies
    principal
    {
        total-policies: uint,
        active-policies: uint,
        total-premiums-paid: uint,
        total-claims-received: uint
    }
)

;; Pool statistics
(define-map pool-stats
    uint ;; block range for stats
    {
        total-premiums-collected: uint,
        total-claims-paid: uint,
        active-policies-count: uint,
        pool-utilization-rate: uint
    }
)

;; Risk assessment multipliers by tier
(define-map tier-risk-multipliers
    uint ;; tier
    uint ;; multiplier (basis points)
)

;; Policy ID counter
(define-data-var next-policy-id uint u1)

;; Initialize tier risk multipliers
(map-set tier-risk-multipliers u0 u100) ;; Small tier: 1x multiplier
(map-set tier-risk-multipliers u1 u120) ;; Medium tier: 1.2x multiplier  
(map-set tier-risk-multipliers u2 u150) ;; Large tier: 1.5x multiplier

;; Purchase insurance policy
(define-public (purchase-insurance (lottery-tier uint) (insured-amount uint) (lottery-duration uint))
    (let (
        (policy-id (var-get next-policy-id))
        (premium (calculate-premium lottery-tier insured-amount))
        (user-stats (default-to {total-policies: u0, active-policies: u0, total-premiums-paid: u0, total-claims-received: u0}
            (map-get? user-policies tx-sender)))
    )
        ;; Validation checks
        (asserts! (>= insured-amount (var-get min-policy-amount)) err-invalid-amount)
        (asserts! (<= lottery-tier u2) err-invalid-tier)
        (asserts! (> lottery-duration u0) err-invalid-amount)
        
        ;; Transfer premium to contract
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        
        ;; Add premium to insurance pool
        (var-set insurance-pool (+ (var-get insurance-pool) premium))
        
        ;; Create insurance policy
        (map-set insurance-policies {user: tx-sender, policy-id: policy-id} {
            lottery-tier: lottery-tier,
            insured-amount: insured-amount,
            premium-paid: premium,
            purchase-block: stacks-block-height,
            expiry-block: (+ stacks-block-height lottery-duration (var-get claim-delay-blocks)),
            is-active: true,
            claimed: false,
            lottery-entry-block: u0
        })
        
        ;; Update user statistics
        (map-set user-policies tx-sender {
            total-policies: (+ (get total-policies user-stats) u1),
            active-policies: (+ (get active-policies user-stats) u1),
            total-premiums-paid: (+ (get total-premiums-paid user-stats) premium),
            total-claims-received: (get total-claims-received user-stats)
        })
        
        ;; Increment policy counter
        (var-set next-policy-id (+ policy-id u1))
        
        (ok policy-id)
    )
)

;; Register lottery entry (must be called when entering lottery)
(define-public (register-lottery-entry (policy-id uint))
    (let (
        (policy (unwrap! (map-get? insurance-policies {user: tx-sender, policy-id: policy-id}) err-policy-not-found))
    )
        (asserts! (get is-active policy) err-policy-not-found)
        (asserts! (< stacks-block-height (get expiry-block policy)) err-policy-expired)
        
        ;; Update lottery entry block
        (map-set insurance-policies {user: tx-sender, policy-id: policy-id}
            (merge policy {lottery-entry-block: stacks-block-height}))
            
        (ok true)
    )
)

;; File insurance claim for losing lottery entry
(define-public (file-claim (policy-id uint))
    (let (
        (policy (unwrap! (map-get? insurance-policies {user: tx-sender, policy-id: policy-id}) err-policy-not-found))
        (payout-amount (/ (* (get insured-amount policy) (var-get payout-percentage)) u10000))
        (user-stats (default-to {total-policies: u0, active-policies: u0, total-premiums-paid: u0, total-claims-received: u0}
            (map-get? user-policies tx-sender)))
    )
        ;; Validation checks
        (asserts! (get is-active policy) err-policy-not-found)
        (asserts! (not (get claimed policy)) err-already-claimed)
        (asserts! (< stacks-block-height (get expiry-block policy)) err-policy-expired)
        (asserts! (> (get lottery-entry-block policy) u0) err-claim-too-early)
        (asserts! (>= (var-get insurance-pool) payout-amount) err-pool-insufficient)
        (asserts! (>= (- stacks-block-height (get lottery-entry-block policy)) (var-get claim-delay-blocks)) err-claim-too-early)
        
        ;; Process payout
        (try! (as-contract (stx-transfer? payout-amount tx-sender tx-sender)))
        
        ;; Update insurance pool
        (var-set insurance-pool (- (var-get insurance-pool) payout-amount))
        
        ;; Mark policy as claimed and inactive
        (map-set insurance-policies {user: tx-sender, policy-id: policy-id}
            (merge policy {
                claimed: true,
                is-active: false
            }))
            
        ;; Update user statistics
        (map-set user-policies tx-sender {
            total-policies: (get total-policies user-stats),
            active-policies: (if (> (get active-policies user-stats) u0) 
                (- (get active-policies user-stats) u1) u0),
            total-premiums-paid: (get total-premiums-paid user-stats),
            total-claims-received: (+ (get total-claims-received user-stats) payout-amount)
        })
        
        (ok payout-amount)
    )
)

;; Calculate insurance premium based on tier and amount
(define-read-only (calculate-premium (lottery-tier uint) (insured-amount uint))
    (let (
        (base-premium (/ (* insured-amount (var-get base-premium-rate)) u10000))
        (tier-multiplier (default-to u100 (map-get? tier-risk-multipliers lottery-tier)))
    )
        (/ (* base-premium tier-multiplier) u100)
    )
)

;; Get policy information
(define-read-only (get-policy (user principal) (policy-id uint))
    (map-get? insurance-policies {user: user, policy-id: policy-id})
)

;; Get user policy statistics
(define-read-only (get-user-stats (user principal))
    (default-to {total-policies: u0, active-policies: u0, total-premiums-paid: u0, total-claims-received: u0}
        (map-get? user-policies user))
)

;; Get insurance pool status
(define-read-only (get-pool-status)
    {
        pool-balance: (var-get insurance-pool),
        base-premium-rate: (var-get base-premium-rate),
        payout-percentage: (var-get payout-percentage),
        min-policy-amount: (var-get min-policy-amount),
        claim-delay-blocks: (var-get claim-delay-blocks)
    }
)

;; Admin function to add funds to insurance pool
(define-public (fund-insurance-pool (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) amount))
        (ok true)
    )
)

;; Admin function to adjust premium rates
(define-public (set-premium-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-rate u2000) err-invalid-amount) ;; Max 20% premium
        (var-set base-premium-rate new-rate)
        (ok true)
    )
)

;; Admin function to adjust payout percentage
(define-public (set-payout-percentage (new-percentage uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-percentage u9000) err-invalid-amount) ;; Max 90% payout
        (asserts! (>= new-percentage u5000) err-invalid-amount) ;; Min 50% payout
        (var-set payout-percentage new-percentage)
        (ok true)
    )
)

;; Admin function to update tier risk multipliers
(define-public (update-tier-multiplier (tier uint) (multiplier uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= tier u2) err-invalid-tier)
        (asserts! (<= multiplier u300) err-invalid-amount) ;; Max 3x multiplier
        (map-set tier-risk-multipliers tier multiplier)
        (ok true)
    )
)

;; Emergency function to withdraw excess funds
(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= (var-get insurance-pool) amount) err-pool-insufficient)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set insurance-pool (- (var-get insurance-pool) amount))
        (ok true)
    )
)
