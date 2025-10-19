;; ------------------------------------------------------------
;; MultiSig Wallet - Clarity v3
;; ------------------------------------------------------------

;; ---------- Constants ----------
(define-constant ERR-UNAUTHORIZED  (err u100))
(define-constant ERR-BAD-ARGS     (err u101))
(define-constant ERR-NOT-FOUND    (err u102))
(define-constant ERR-ALREADY      (err u103))
(define-constant ERR-INSUFFICIENT (err u104))
(define-constant ERR-PAUSED       (err u105))

;; ---------- Data / State ----------
(define-data-var deployer principal tx-sender)
(define-data-var initialized bool false)

;; Owners list (kept for easy frontend reads) - max 20 owners
(define-data-var owners-list (list 20 principal) (list))
;; Mapping for quick owner existence checks
(define-map owners
  { owner: principal }
  { exists: bool })

(define-data-var threshold uint u0)      ;; approvals required

;; Transactions storage
;; tx: { proposer, to, amount, token (optional principal), executed, approvals }
(define-data-var next-tx-id uint u1)
(define-map txs
  { id: uint }
  {
    proposer: principal,
    to: principal,
    amount: uint,
    token: (optional principal),
    executed: bool,
    approvals: uint
  })

;; Per-owner approvals: approvals { id, owner } -> { approved: bool }
(define-map approvals
  { id: uint, owner: principal }
  { approved: bool })

;; Pause switch
(define-data-var paused bool false)

;; ---------- Helpers ----------
(define-read-only (is-owner (p principal))
  (is-some (map-get? owners { owner: p })))

(define-read-only (is-initialized) (var-get initialized))
(define-read-only (not-paused) (not (var-get paused)))

;; ---------- Initialization (call once by deployer) ----------
(define-public (initialize (owners-list-param (list 20 principal)) (req-threshold uint))
    (begin
        (asserts! (is-eq tx-sender (var-get deployer)) ERR-UNAUTHORIZED)
        (asserts! (not (var-get initialized)) ERR-ALREADY)
        (asserts! (>= (len owners-list-param) u1) ERR-BAD-ARGS)
        (asserts! (> req-threshold u0) ERR-BAD-ARGS)
        
        (var-set owners-list owners-list-param)
        (var-set threshold req-threshold)
        (var-set initialized true)
        (map-set owners { owner: (unwrap! (element-at owners-list-param u0) ERR-BAD-ARGS) } { exists: true })
        (ok true)))

;; ---------- Pause control (deployer) ----------
(define-public (pause)
  (begin
    (asserts! (is-eq tx-sender (var-get deployer)) ERR-UNAUTHORIZED)
    (var-set paused true)
    (ok true)))

(define-public (unpause)
  (begin
    (asserts! (is-eq tx-sender (var-get deployer)) ERR-UNAUTHORIZED)
    (var-set paused false)
    (ok true)))

;; ---------- Propose a transaction ----------
;; For this version, we only support STX transfers
(define-public (propose (to principal) (amount uint))
  (begin
    (asserts! (is-initialized) ERR-BAD-ARGS)
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (asserts! (is-owner tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-BAD-ARGS)
    (asserts! (not (is-eq to tx-sender)) ERR-BAD-ARGS) ;; Can't send to self
    
    (let ((id (var-get next-tx-id)))
      (asserts! (create-tx id to amount) ERR-BAD-ARGS)
      (asserts! (approve-tx id tx-sender) ERR-BAD-ARGS)
      (var-set next-tx-id (+ id u1))
      (ok id))))

(define-private (create-tx (id uint) (to principal) (amount uint))
    (begin
        (map-set txs { id: id }
            {
                proposer: tx-sender,
                to: to,
                amount: amount,
                token: none, ;; For this version, we only support STX
                executed: false,
                approvals: u0
            })
        true))

(define-private (approve-tx (id uint) (owner principal))
    (begin
        (map-set approvals { id: id, owner: owner } { approved: true })
        (match (map-get? txs { id: id })
            tx (begin 
                (map-set txs { id: id }
                    (merge tx { approvals: (+ (get approvals tx) u1) }))
                true)
            false)))

;; ---------- Approve a transaction ----------
(define-public (approve (id uint))
    (let ((tx (unwrap! (map-get? txs { id: id }) ERR-NOT-FOUND)))
        (begin
            (asserts! (is-owner tx-sender) ERR-UNAUTHORIZED)
            (asserts! (not (get executed tx)) ERR-ALREADY)
            (asserts! (is-none (map-get? approvals { id: id, owner: tx-sender })) ERR-ALREADY)
            (asserts! (approve-tx id tx-sender) ERR-NOT-FOUND)
            (ok true))))

;; ---------- Revoke approval ----------
(define-public (revoke (id uint))
    (let ((tx (unwrap! (map-get? txs { id: id }) ERR-NOT-FOUND)))
        (begin
            (asserts! (is-owner tx-sender) ERR-UNAUTHORIZED)
            (asserts! (not (get executed tx)) ERR-ALREADY)
            (asserts! (is-some (map-get? approvals { id: id, owner: tx-sender })) ERR-NOT-FOUND)
            (asserts! (revoke-tx id tx-sender tx) ERR-NOT-FOUND)
            (ok true))))

(define-private (revoke-tx (id uint) (owner principal) (tx { proposer: principal, to: principal, amount: uint, token: (optional principal), executed: bool, approvals: uint }))
    (begin
        (map-delete approvals { id: id, owner: owner })
        (map-set txs { id: id }
            (merge tx { approvals: (- (get approvals tx) u1) }))
        true))

;; ---------- Cancel proposal (proposer only, before execution) ----------
(define-public (cancel (id uint))
    (let ((tx (unwrap! (map-get? txs { id: id }) ERR-NOT-FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get proposer tx)) ERR-UNAUTHORIZED)
            (asserts! (not (get executed tx)) ERR-ALREADY)
            (asserts! (mark-executed 
                id
                (get proposer tx)
                (get to tx)
                (get amount tx)
                (get token tx)
                (get executed tx)
                (get approvals tx)) ERR-BAD-ARGS)
            (ok true))))

(define-private (mark-executed (id uint) (proposer principal) (to principal) (amount uint) (token (optional principal)) (executed bool) (sig-count uint))
    (let ((valid-tx (map-get? txs { id: id })))
        (if (and 
            (is-some valid-tx)
            (let ((tx (unwrap-panic valid-tx)))
                (and 
                    (is-eq (get proposer tx) proposer)
                    (is-eq (get to tx) to)
                    (is-eq (get amount tx) amount)
                    (is-eq (get token tx) token)
                    (is-eq (get executed tx) executed)
                    (is-eq (get approvals tx) sig-count))))
            (begin
                (map-set txs 
                    { id: id }
                    { 
                        proposer: proposer,
                        to: to,
                        amount: amount,
                        token: token,
                        executed: true,
                        approvals: sig-count 
                    })
                true)
            false)))

;; ---------- Execute (anyone) ----------
(define-public (execute (id uint))
    (let ((tx (unwrap! (map-get? txs { id: id }) ERR-NOT-FOUND)))
        (begin
            (asserts! (not (get executed tx)) ERR-ALREADY)
            (asserts! (>= (get approvals tx) (var-get threshold)) ERR-INSUFFICIENT)
            (let ((amount (get amount tx))
                  (recipient (get to tx)))
                (begin
                    (try! (stx-transfer? amount (as-contract tx-sender) recipient))
                    (asserts! (mark-executed 
                        id
                        (get proposer tx)
                        (get to tx)
                        (get amount tx)
                        (get token tx)
                        (get executed tx)
                        (get approvals tx)) ERR-BAD-ARGS)
                    (ok true))))))

;; ---------- Views ----------
(define-read-only (get-tx (id uint))
    (match (map-get? txs { id: id })
        tx (ok tx)
        ERR-NOT-FOUND))

(define-read-only (get-owners)
    (ok (var-get owners-list)))

(define-read-only (get-threshold)
    (ok (var-get threshold)))

(define-read-only (is-approved (id uint) (who principal))
    (ok (is-some (map-get? approvals { id: id, owner: who }))))

(define-read-only (get-next-tx-id)
    (ok (var-get next-tx-id)))

(define-read-only (is-paused)
    (ok (var-get paused)))
