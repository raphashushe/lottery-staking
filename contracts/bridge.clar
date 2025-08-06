(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u3000))
(define-constant err-invalid-chain (err u3001))
(define-constant err-insufficient-balance (err u3002))
(define-constant err-bridge-paused (err u3003))
(define-constant err-invalid-operator (err u3004))
(define-constant err-already-processed (err u3005))
(define-constant err-invalid-amount (err u3006))

(define-data-var bridge-paused bool false)
(define-data-var bridge-fee uint u100)
(define-data-var next-deposit-id uint u1)

(define-map supported-chains
    uint
    {
        chain-name: (string-ascii 20),
        enabled: bool,
        min-deposit: uint,
        max-deposit: uint
    }
)

(define-map bridge-operators
    principal
    bool
)

(define-map user-balances
    {user: principal, chain: uint}
    uint
)

(define-map deposit-records
    uint
    {
        user: principal,
        chain-ids: uint,
        amount: uint,
        tx-hash: (string-ascii 64),
        processed: bool,
        block-height: uint
    }
)

(define-map withdrawal-requests
    uint
    {
        user: principal,
        chain-idd: uint,
        amount: uint,
        target-address: (string-ascii 64),
        processed: bool,
        block-height: uint
    }
)

(define-data-var next-withdrawal-id uint u1)

(define-public (add-bridge-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set bridge-operators operator true)
        (ok true)
    )
)

(define-public (remove-bridge-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set bridge-operators operator false)
        (ok true)
    )
)

(define-public (add-supported-chain (chain-key uint) (chain-name (string-ascii 20)) (min-deposit uint) (max-deposit uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set supported-chains chain-key {
            chain-name: chain-name,
            enabled: true,
            min-deposit: min-deposit,
            max-deposit: max-deposit
        })
        (ok true)
    )
)

(define-public (toggle-chain (chain-key uint) (enabled bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let (
            (chain (unwrap! (map-get? supported-chains chain-key) err-invalid-chain))
        )
            (map-set supported-chains chain-key (merge chain {enabled: enabled}))
            (ok true)
        )
    )
)

(define-public (process-deposit (user principal) (deposit-chain-id uint) (amount uint) (tx-hash (string-ascii 64)))
    (begin
        (asserts! (not (var-get bridge-paused)) err-bridge-paused)
        (asserts! (default-to false (map-get? bridge-operators tx-sender)) err-invalid-operator)
        
        (let (
            (chain (unwrap! (map-get? supported-chains deposit-chain-id) err-invalid-chain))
            (deposit-id (var-get next-deposit-id))
        )
            (asserts! (get enabled chain) err-invalid-chain)
            (asserts! (>= amount (get min-deposit chain)) err-invalid-amount)
            (asserts! (<= amount (get max-deposit chain)) err-invalid-amount)
            
            (map-set deposit-records deposit-id {
                user: user,
                chain-ids: deposit-chain-id,
                amount: amount,
                tx-hash: tx-hash,
                processed: true,
                block-height: stacks-block-height
            })
            
            (map-set user-balances 
                {user: user, chain: deposit-chain-id}
                (+ amount (default-to u0 (map-get? user-balances {user: user, chain: deposit-chain-id}))))
            
            (var-set next-deposit-id (+ deposit-id u1))
            (ok deposit-id)
        )
    )
)

(define-public (request-withdrawal (withdraw-chain-id uint) (amount uint) (target-address (string-ascii 64)))
    (begin
        (asserts! (not (var-get bridge-paused)) err-bridge-paused)
        
        (let (
            (chain (unwrap! (map-get? supported-chains withdraw-chain-id) err-invalid-chain))
            (user-balance (default-to u0 (map-get? user-balances {user: tx-sender, chain: withdraw-chain-id})))
            (withdrawal-id (var-get next-withdrawal-id))
            (fee-amount (/ (* amount (var-get bridge-fee)) u10000))
            (net-amount (- amount fee-amount))
        )
            (asserts! (get enabled chain) err-invalid-chain)
            (asserts! (>= user-balance amount) err-insufficient-balance)
            (asserts! (> amount u0) err-invalid-amount)
            
            (map-set user-balances 
                {user: tx-sender, chain: withdraw-chain-id}
                (- user-balance amount))
            
            (map-set withdrawal-requests withdrawal-id {
                user: tx-sender,
                chain-idd: withdraw-chain-id,
                amount: net-amount,
                target-address: target-address,
                processed: false,
                block-height: stacks-block-height
            })
            
            (var-set next-withdrawal-id (+ withdrawal-id u1))
            (ok withdrawal-id)
        )
    )
)

(define-public (process-withdrawal (withdrawal-id uint))
    (begin
        (asserts! (default-to false (map-get? bridge-operators tx-sender)) err-invalid-operator)
        
        (let (
            (withdrawal (unwrap! (map-get? withdrawal-requests withdrawal-id) err-invalid-amount))
        )
            (asserts! (not (get processed withdrawal)) err-already-processed)
            
            (map-set withdrawal-requests withdrawal-id 
                (merge withdrawal {processed: true}))
            (ok true)
        )
    )
)

(define-public (enter-lottery-cross-chain (tier uint) (amount uint) (lottery-chain-id uint))
    (begin
        (asserts! (not (var-get bridge-paused)) err-bridge-paused)
        
        (let (
            (user-balance (default-to u0 (map-get? user-balances {user: tx-sender, chain: lottery-chain-id})))
            (chain (unwrap! (map-get? supported-chains lottery-chain-id) err-invalid-chain))
        )
            (asserts! (get enabled chain) err-invalid-chain)
            (asserts! (>= user-balance amount) err-insufficient-balance)
            
            (map-set user-balances 
                {user: tx-sender, chain: lottery-chain-id}
                (- user-balance amount))
            
            (try! (contract-call? .lottery enter-lottery tier amount))
            (ok true)
        )
    )
)

(define-public (claim-cross-chain-winnings (tier uint) (lottery-chain-id uint))
    (begin
        (let (
            (chain (unwrap! (map-get? supported-chains lottery-chain-id) err-invalid-chain))
        )
            (asserts! (get enabled chain) err-invalid-chain)
            (ok true)
        )
    )
)

(define-public (set-bridge-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-amount)
        (var-set bridge-fee new-fee)
        (ok new-fee)
    )
)

(define-public (toggle-bridge (paused bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set bridge-paused paused)
        (ok paused)
    )
)

(define-public (emergency-withdraw (user principal) (emergency-chain-id uint) (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (var-get bridge-paused) err-bridge-paused)
        
        (let (
            (user-balance (default-to u0 (map-get? user-balances {user: user, chain: emergency-chain-id})))
        )
            (asserts! (>= user-balance amount) err-insufficient-balance)
            
            (map-set user-balances 
                {user: user, chain: emergency-chain-id}
                (- user-balance amount))
            (ok true)
        )
    )
)

(define-read-only (get-user-balance (user principal) (balance-chain-id uint))
    (default-to u0 (map-get? user-balances {user: user, chain: balance-chain-id}))
)

(define-read-only (get-supported-chain (chain-key uint))
    (map-get? supported-chains chain-key)
)

(define-read-only (get-deposit-record (deposit-id uint))
    (map-get? deposit-records deposit-id)
)

(define-read-only (get-withdrawal-request (withdrawal-id uint))
    (map-get? withdrawal-requests withdrawal-id)
)

(define-read-only (is-bridge-operator (operator principal))
    (default-to false (map-get? bridge-operators operator))
)

(define-read-only (get-bridge-status)
    {
        paused: (var-get bridge-paused),
        fee: (var-get bridge-fee),
        next-deposit-id: (var-get next-deposit-id),
        next-withdrawal-id: (var-get next-withdrawal-id)
    }
)