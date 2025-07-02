(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u4000))
(define-constant err-market-not-found (err u4001))
(define-constant err-market-closed (err u4002))
(define-constant err-insufficient-bet (err u4003))
(define-constant err-market-resolved (err u4004))
(define-constant err-invalid-outcome (err u4005))
(define-constant err-not-oracle (err u4006))
(define-constant err-min-bet-too-low (err u4007))

(define-data-var next-market-id uint u1)
(define-data-var platform-fee uint u200)

(define-map prediction-markets
    uint
    {
        title: (string-ascii 100),
        description: (string-ascii 200),
        creator: principal,
        min-bet: uint,
        end-block: uint,
        outcome-count: uint,
        total-pool: uint,
        resolved: bool,
        winning-outcome: (optional uint),
        created-block: uint
    }
)

(define-map market-outcomes
    {market-id: uint, outcome-id: uint}
    {
        description: (string-ascii 100),
        total-bets: uint,
        odds: uint
    }
)

(define-map user-bets
    {market-id: uint, user: principal, outcome-id: uint}
    uint
)

(define-map market-oracles
    uint
    (list 10 principal)
)

(define-map oracle-votes
    {market-id: uint, oracle: principal}
    uint
)

(define-map user-market-stats
    principal
    {
        total-markets-created: uint,
        total-bets-placed: uint,
        total-winnings: uint,
        win-rate: uint
    }
)

(define-public (create-prediction-market 
    (title (string-ascii 100))
    (description (string-ascii 200))
    (min-bet uint)
    (duration uint)
    (outcome-descriptions (list 10 (string-ascii 100))))
    (begin
        (asserts! (> min-bet u0) err-min-bet-too-low)
        (asserts! (> duration u0) (err u4008))
        (asserts! (> (len outcome-descriptions) u1) (err u4009))
        
        (let (
            (market-id (var-get next-market-id))
            (outcome-count (len outcome-descriptions))
        )
            (map-set prediction-markets market-id {
                title: title,
                description: description,
                creator: tx-sender,
                min-bet: min-bet,
                end-block: (+ stacks-block-height duration),
                outcome-count: outcome-count,
                total-pool: u0,
                resolved: false,
                winning-outcome: none,
                created-block: stacks-block-height
            })
            
            (fold setup-outcome outcome-descriptions {market-id: market-id, outcome-id: u0})
            (var-set next-market-id (+ market-id u1))
            
            (let (
                (user-stats (default-to {total-markets-created: u0, total-bets-placed: u0, total-winnings: u0, win-rate: u0}
                    (map-get? user-market-stats tx-sender)))
            )
                (map-set user-market-stats tx-sender
                    (merge user-stats {total-markets-created: (+ (get total-markets-created user-stats) u1)}))
            )
            
            (ok market-id)
        )
    )
)

(define-private (setup-outcome (description (string-ascii 100)) (acc {market-id: uint, outcome-id: uint}))
    (begin
        (map-set market-outcomes 
            {market-id: (get market-id acc), outcome-id: (get outcome-id acc)}
            {
                description: description,
                total-bets: u0,
                odds: u100
            })
        {market-id: (get market-id acc), outcome-id: (+ (get outcome-id acc) u1)}
    )
)

(define-public (place-bet (market-id uint) (outcome-id uint) (amount uint))
    (let (
        (market (unwrap! (map-get? prediction-markets market-id) err-market-not-found))
        (outcome (unwrap! (map-get? market-outcomes {market-id: market-id, outcome-id: outcome-id}) err-invalid-outcome))
        (current-bet (default-to u0 (map-get? user-bets {market-id: market-id, user: tx-sender, outcome-id: outcome-id})))
    )
        (asserts! (not (get resolved market)) err-market-resolved)
        (asserts! (< stacks-block-height (get end-block market)) err-market-closed)
        (asserts! (>= amount (get min-bet market)) err-insufficient-bet)
        (asserts! (< outcome-id (get outcome-count market)) err-invalid-outcome)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set prediction-markets market-id
            (merge market {total-pool: (+ (get total-pool market) amount)}))
            
        (map-set market-outcomes 
            {market-id: market-id, outcome-id: outcome-id}
            (merge outcome {total-bets: (+ (get total-bets outcome) amount)}))
            
        (map-set user-bets 
            {market-id: market-id, user: tx-sender, outcome-id: outcome-id}
            (+ current-bet amount))
            
        (let (
            (user-stats (default-to {total-markets-created: u0, total-bets-placed: u0, total-winnings: u0, win-rate: u0}
                (map-get? user-market-stats tx-sender)))
        )
            (map-set user-market-stats tx-sender
                (merge user-stats {total-bets-placed: (+ (get total-bets-placed user-stats) u1)}))
        )
        
        (ok true)
    )
)

(define-public (add-market-oracle (market-id uint) (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (current-oracles (default-to (list) (map-get? market-oracles market-id)))
        )
            (map-set market-oracles market-id
                (unwrap! (as-max-len? (append current-oracles oracle) u10) (err u4010)))
            (ok true)
        )
    )
)

(define-public (oracle-vote (market-id uint) (winning-outcome uint))
    (let (
        (market (unwrap! (map-get? prediction-markets market-id) err-market-not-found))
        (oracles (default-to (list) (map-get? market-oracles market-id)))
    )
        (asserts! (not (get resolved market)) err-market-resolved)
        (asserts! (>= stacks-block-height (get end-block market)) err-market-closed)
        (asserts! (is-some (index-of oracles tx-sender)) err-not-oracle)
        (asserts! (< winning-outcome (get outcome-count market)) err-invalid-outcome)
        
        (map-set oracle-votes 
            {market-id: market-id, oracle: tx-sender}
            winning-outcome)
        (ok true)
    )
)

(define-public (resolve-market (market-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (market (unwrap! (map-get? prediction-markets market-id) err-market-not-found))
            (winning-outcome (unwrap! (calculate-winning-outcome market-id) (err u4011)))
        )
            (asserts! (not (get resolved market)) err-market-resolved)
            (asserts! (>= stacks-block-height (get end-block market)) err-market-closed)
            
            (map-set prediction-markets market-id
                (merge market {
                    resolved: true,
                    winning-outcome: (some winning-outcome)
                }))
            (ok winning-outcome)
        )
    )
)

(define-private (calculate-winning-outcome (market-id uint))
    (let (
        (oracles (default-to (list) (map-get? market-oracles market-id)))
    )
        (if (> (len oracles) u0)
            (some u0)
            none
        )
    )
)

(define-public (claim-winnings (market-id uint) (outcome-id uint))
    (let (
        (market (unwrap! (map-get? prediction-markets market-id) err-market-not-found))
        (user-bet (default-to u0 (map-get? user-bets {market-id: market-id, user: tx-sender, outcome-id: outcome-id})))
        (winning-outcome (unwrap! (get winning-outcome market) (err u4012)))
        (outcome (unwrap! (map-get? market-outcomes {market-id: market-id, outcome-id: outcome-id}) err-invalid-outcome))
    )
        (asserts! (get resolved market) (err u4013))
        (asserts! (is-eq outcome-id winning-outcome) (err u4014))
        (asserts! (> user-bet u0) (err u4015))
        
        (let (
            (total-winning-bets (get total-bets outcome))
            (total-pool (get total-pool market))
            (platform-fee-amount (/ (* total-pool (var-get platform-fee)) u10000))
            (prize-pool (- total-pool platform-fee-amount))
            (user-share (/ (* prize-pool user-bet) total-winning-bets))
        )
            (map-delete user-bets {market-id: market-id, user: tx-sender, outcome-id: outcome-id})
            
            (let (
                (user-stats (default-to {total-markets-created: u0, total-bets-placed: u0, total-winnings: u0, win-rate: u0}
                    (map-get? user-market-stats tx-sender)))
            )
                (map-set user-market-stats tx-sender
                    (merge user-stats {total-winnings: (+ (get total-winnings user-stats) user-share)}))
            )
            
            (try! (as-contract (stx-transfer? user-share tx-sender tx-sender)))
            (ok user-share)
        )
    )
)

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) (err u4016))
        (var-set platform-fee new-fee)
        (ok new-fee)
    )
)

(define-public (emergency-refund (market-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (market (unwrap! (map-get? prediction-markets market-id) err-market-not-found))
        )
            (map-set prediction-markets market-id
                (merge market {resolved: true, winning-outcome: none}))
            (ok true)
        )
    )
)

(define-read-only (get-market (market-id uint))
    (map-get? prediction-markets market-id)
)

(define-read-only (get-market-outcome (market-id uint) (outcome-id uint))
    (map-get? market-outcomes {market-id: market-id, outcome-id: outcome-id})
)

(define-read-only (get-user-bet (market-id uint) (user principal) (outcome-id uint))
    (default-to u0 (map-get? user-bets {market-id: market-id, user: user, outcome-id: outcome-id}))
)

(define-read-only (get-user-stats (user principal))
    (default-to {total-markets-created: u0, total-bets-placed: u0, total-winnings: u0, win-rate: u0}
        (map-get? user-market-stats user))
)

(define-read-only (get-market-oracles (market-id uint))
    (default-to (list) (map-get? market-oracles market-id))
)

(define-read-only (get-platform-status)
    {
        next-market-id: (var-get next-market-id),
        platform-fee: (var-get platform-fee)
    }
)

(define-read-only (calculate-potential-winnings (market-id uint) (outcome-id uint) (bet-amount uint))
    (let (
        (market (unwrap! (map-get? prediction-markets market-id) (err u0)))
        (outcome (unwrap! (map-get? market-outcomes {market-id: market-id, outcome-id: outcome-id}) (err u0)))
        (total-pool (+ (get total-pool market) bet-amount))
        (total-outcome-bets (+ (get total-bets outcome) bet-amount))
        (platform-fee-amount (/ (* total-pool (var-get platform-fee)) u10000))
        (prize-pool (- total-pool platform-fee-amount))
    )
        (if (> total-outcome-bets u0)
            (ok (/ (* prize-pool bet-amount) total-outcome-bets))
            (ok u0))
    )
)
