;; wavedao-governance.clar
;; This contract implements the governance system for WaveDAO, allowing token holders to create, vote on,
;; and execute proposals that shape the platform's future. Members can submit proposals for changes to
;; platform features, fee structures, promotion mechanisms, or treasury allocations.

;; =========================================
;; Constants and Error Codes
;; =========================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-PROPOSAL-ALREADY-EXISTS (err u102))
(define-constant ERR-PROPOSAL-CLOSED (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INSUFFICIENT-TOKENS (err u105))
(define-constant ERR-VOTING-PERIOD-NOT-ENDED (err u106))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u107))
(define-constant ERR-INVALID-PROPOSAL-TYPE (err u108))
(define-constant ERR-INVALID-VOTE-OPTION (err u109))
(define-constant ERR-ZERO-VOTE-WEIGHT (err u110))

;; Proposal types
(define-constant PROPOSAL-TYPE-FEATURE u1)
(define-constant PROPOSAL-TYPE-FEE u2)
(define-constant PROPOSAL-TYPE-PROMOTION u3)
(define-constant PROPOSAL-TYPE-TREASURY u4)

;; Vote options
(define-constant VOTE-FOR u1)
(define-constant VOTE-AGAINST u2)
(define-constant VOTE-ABSTAIN u3)

;; Governance settings
(define-constant REQUIRED-THRESHOLD u600) ;; 60% approval needed (out of 1000)
(define-constant MINIMUM-QUORUM u200) ;; 20% participation required (out of 1000)
(define-constant PROPOSAL-DURATION u1440) ;; Duration in blocks (approximately 10 days at 10 min blocks)
(define-constant ARTIST-VOTE-MULTIPLIER u2) ;; Artists get 2x voting power

;; Admin
(define-constant CONTRACT-OWNER tx-sender)

;; =========================================
;; Data Maps and Variables
;; =========================================

;; Each proposal contains all relevant metadata
(define-map proposals
  { proposal-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-utf8 1000),
    proposal-type: uint,
    creation-block: uint,
    execution-block: (optional uint),
    is-executed: bool,
    target-contract: (optional principal),
    target-function: (optional (string-ascii 128)),
    target-args: (optional (list 10 (string-utf8 100))),
    votes-for: uint,
    votes-against: uint,
    votes-abstain: uint,
    total-vote-weight: uint
  }
)

;; Track which proposals each user has voted on and how
(define-map user-votes
  { proposal-id: uint, voter: principal }
  { vote-option: uint, vote-weight: uint }
)

;; Track which addresses are verified artists (for extra voting power)
(define-map is-artist
  { address: principal }
  { verified: bool }
)

;; Track total proposals created
(define-data-var proposal-count uint u0)

;; =========================================
;; Private Functions
;; =========================================

;; Get the token balance of a user from the token contract
(define-private (get-token-balance (user principal))
  (contract-call? .wavedao-token get-balance user)
)

;; Check if a user is a verified artist
(define-private (is-verified-artist (user principal))
  (default-to false (get verified (map-get? is-artist { address: user })))
)

;; Calculate voting weight for a user
;; Artists get extra voting power through the multiplier
(define-private (calculate-vote-weight (user principal))
  (let (
    (token-balance (get-token-balance user))
    (artist-multiplier (if (is-verified-artist user) ARTIST-VOTE-MULTIPLIER u1))
  )
    (* token-balance artist-multiplier)
  )
)

;; Check if a proposal exists
(define-private (proposal-exists (proposal-id uint))
  (is-some (map-get? proposals { proposal-id: proposal-id }))
)

;; Check if a proposal is still in voting period
(define-private (is-voting-active (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) false))
    (current-block block-height)
    (end-block (+ (get creation-block proposal) PROPOSAL-DURATION))
  )
    (<= current-block end-block)
  )
)

;; Check if a user has already voted on a proposal
(define-private (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? user-votes { proposal-id: proposal-id, voter: voter }))
)

;; Check if a proposal has passed and can be executed
(define-private (can-execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) false))
    (current-block block-height)
    (end-block (+ (get creation-block proposal) PROPOSAL-DURATION))
    (total-votes (get total-vote-weight proposal))
    (for-votes (get votes-for proposal))
    (total-supply (contract-call? .wavedao-token get-total-supply))
    (quorum-reached (>= (* total-votes u1000) (* total-supply MINIMUM-QUORUM)))
    (approval-threshold-met (>= (* for-votes u1000) (* total-votes REQUIRED-THRESHOLD)))
  )
    (and
      (> current-block end-block)    ;; Voting period ended
      (not (get is-executed proposal)) ;; Not already executed
      quorum-reached                   ;; Minimum participation met
      approval-threshold-met           ;; Required approval threshold met
    )
  )
)

;; =========================================
;; Read-Only Functions
;; =========================================

;; Get details of a specific proposal
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Get a user's vote on a specific proposal
(define-read-only (get-user-vote (proposal-id uint) (voter principal))
  (map-get? user-votes { proposal-id: proposal-id, voter: voter })
)

;; Get the vote weight for a specific user
(define-read-only (get-vote-weight (user principal))
  (calculate-vote-weight user)
)

;; Get the current proposal count
(define-read-only (get-proposal-count)
  (var-get proposal-count)
)

;; Check if proposal can be voted on
(define-read-only (can-vote (proposal-id uint))
  (and
    (proposal-exists proposal-id)
    (is-voting-active proposal-id)
  )
)

;; Check if proposal can be executed
(define-read-only (check-can-execute (proposal-id uint))
  (can-execute-proposal proposal-id)
)

;; =========================================
;; Public Functions
;; =========================================

;; Create a new proposal
(define-public (create-proposal
  (title (string-ascii 100))
  (description (string-utf8 1000))
  (proposal-type uint)
  (target-contract (optional principal))
  (target-function (optional (string-ascii 128)))
  (target-args (optional (list 10 (string-utf8 100))))
)
  (let (
    (proposal-id (+ (var-get proposal-count) u1))
    (vote-weight (calculate-vote-weight tx-sender))
  )
    ;; Validate proposal type
    (asserts! (or
                (is-eq proposal-type PROPOSAL-TYPE-FEATURE)
                (is-eq proposal-type PROPOSAL-TYPE-FEE)
                (is-eq proposal-type PROPOSAL-TYPE-PROMOTION)
                (is-eq proposal-type PROPOSAL-TYPE-TREASURY))
              ERR-INVALID-PROPOSAL-TYPE)
    
    ;; Ensure creator has some tokens for creating proposals
    (asserts! (> vote-weight u0) ERR-INSUFFICIENT-TOKENS)
    
    ;; Create the proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        creation-block: block-height,
        execution-block: none,
        is-executed: false,
        target-contract: target-contract,
        target-function: target-function,
        target-args: target-args,
        votes-for: u0,
        votes-against: u0,
        votes-abstain: u0,
        total-vote-weight: u0
      }
    )
    
    ;; Increment proposal counter
    (var-set proposal-count proposal-id)
    
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote (proposal-id uint) (vote-option uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
    (vote-weight (calculate-vote-weight tx-sender))
  )
    ;; Validate vote option
    (asserts! (or
                (is-eq vote-option VOTE-FOR)
                (is-eq vote-option VOTE-AGAINST)
                (is-eq vote-option VOTE-ABSTAIN))
              ERR-INVALID-VOTE-OPTION)
    
    ;; Check if voting is still active
    (asserts! (is-voting-active proposal-id) ERR-PROPOSAL-CLOSED)
    
    ;; Check if user has already voted
    (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
    
    ;; Check if user has voting power
    (asserts! (> vote-weight u0) ERR-ZERO-VOTE-WEIGHT)
    
    ;; Record the user's vote
    (map-set user-votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote-option: vote-option, vote-weight: vote-weight }
    )
    
    ;; Update proposal vote counts
    (match vote-option
      VOTE-FOR (map-set proposals { proposal-id: proposal-id }
                  (merge proposal {
                    votes-for: (+ (get votes-for proposal) vote-weight),
                    total-vote-weight: (+ (get total-vote-weight proposal) vote-weight)
                  }))
      VOTE-AGAINST (map-set proposals { proposal-id: proposal-id }
                     (merge proposal {
                       votes-against: (+ (get votes-against proposal) vote-weight),
                       total-vote-weight: (+ (get total-vote-weight proposal) vote-weight)
                     }))
      VOTE-ABSTAIN (map-set proposals { proposal-id: proposal-id }
                     (merge proposal {
                       votes-abstain: (+ (get votes-abstain proposal) vote-weight),
                       total-vote-weight: (+ (get total-vote-weight proposal) vote-weight)
                     }))
    )
    
    (ok true)
  )
)

;; Execute a proposal that has passed
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Check if proposal can be executed
    (asserts! (can-execute-proposal proposal-id) ERR-VOTING-PERIOD-NOT-ENDED)
    
    ;; Mark proposal as executed
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal {
        is-executed: true,
        execution-block: (some block-height)
      })
    )
    
    ;; Implementation would execute the proposal based on its type and target
    ;; This is a simplified version that just marks it as executed
    ;; In a real implementation, you would call the target contract with the specified function and args
    
    (ok true)
  )
)

;; Register a user as a verified artist (admin only)
(define-public (register-artist (artist principal))
  (begin
    ;; Only contract owner can register artists
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    ;; Register the artist
    (map-set is-artist
      { address: artist }
      { verified: true }
    )
    
    (ok true)
  )
)

;; Remove artist verification (admin only)
(define-public (remove-artist (artist principal))
  (begin
    ;; Only contract owner can remove artists
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    ;; Remove the artist verification
    (map-set is-artist
      { address: artist }
      { verified: false }
    )
    
    (ok true)
  )
)