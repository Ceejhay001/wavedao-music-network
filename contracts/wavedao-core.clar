;; wavedao-core
;; This contract serves as the central hub for the WaveDAO music platform, handling:
;; 1. Music registration and ownership
;; 2. Streaming metrics tracking
;; 3. Royalty distribution and subscription management
;; The contract allows artists to tokenize their music, tracks streaming activity,
;; and automatically distributes subscription revenue based on streaming metrics.

;; ===============================================================
;; Constants and Error Codes
;; ===============================================================

;; General errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PARAMETERS (err u103))

;; Music registration errors
(define-constant ERR-INVALID-TITLE (err u200))
(define-constant ERR-INVALID-ARTIST (err u201))
(define-constant ERR-INVALID-SPLIT (err u202))
(define-constant ERR-SPLIT-EXCEEDS-100 (err u203))

;; Streaming errors
(define-constant ERR-NOT-SUBSCRIBED (err u300))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u301))

;; Payment errors
(define-constant ERR-INSUFFICIENT-FUNDS (err u400))
(define-constant ERR-TRANSFER-FAILED (err u401))

;; Treasury constants
(define-constant PLATFORM-FEE-PERCENT u10) ;; 10% platform fee
(define-constant MONTHLY-SUBSCRIPTION-PRICE u10000000) ;; 10 STX (in micro-STX)
(define-constant SUBSCRIPTION-DURATION u2592000) ;; 30 days in seconds

;; Deployer address for platform admin functions
(define-constant CONTRACT-OWNER tx-sender)

;; ===============================================================
;; Data Maps and Variables
;; ===============================================================

;; Represents a registered music track
(define-map tracks
  {track-id: uint}
  {
    title: (string-ascii 100),
    artist-address: principal,
    metadata-url: (string-ascii 255),
    registration-time: uint,
    total-streams: uint,
    royalty-splits: (list 10 {recipient: principal, share-percentage: uint}),
    is-active: bool
  }
)

;; Tracks the next available track ID
(define-data-var next-track-id uint u1)

;; Maps artist addresses to their registered track IDs
(define-map artist-tracks
  {artist: principal}
  {track-ids: (list 100 uint)}
)

;; Stores streaming metrics for each track by period (monthly)
(define-map streaming-metrics
  {track-id: uint, period: uint}
  {streams: uint}
)

;; Records total platform streams by period (monthly)
(define-map platform-metrics
  {period: uint}
  {total-streams: uint, total-revenue: uint}
)

;; User subscription details
(define-map subscriptions
  {user: principal}
  {start-time: uint, end-time: uint, active: bool}
)

;; Platform treasury
(define-data-var treasury-balance uint u0)

;; Current accounting period (increments monthly)
(define-data-var current-period uint u1)

;; ===============================================================
;; Private Functions
;; ===============================================================

;; Validates that tx-sender is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Validates that a track exists
(define-private (track-exists (track-id uint))
  (default-to false (map-get? tracks {track-id: track-id}))
)

;; Validates that tx-sender is the owner of a track
(define-private (is-track-owner (track-id uint))
  (let ((track-info (unwrap! (map-get? tracks {track-id: track-id}) false)))
    (is-eq tx-sender (get artist-address track-info))
  )
)

;; Validates that the royalty splits add up to 100%
(define-private (validate-splits (splits (list 10 {recipient: principal, share-percentage: uint})))
  (let ((total-percentage (fold + (map get-percentage splits) u0)))
    (if (is-eq total-percentage u100)
      true
      false
    )
  )
)

;; Helper function to extract percentage from split structure
(define-private (get-percentage (split {recipient: principal, share-percentage: uint}))
  (get share-percentage split)
)

;; Checks if a user has an active subscription
(define-private (is-subscribed (user principal))
  (let ((subscription (default-to {start-time: u0, end-time: u0, active: false} 
                       (map-get? subscriptions {user: user}))))
    (and
      (get active subscription)
      (<= block-height (get end-time subscription))
    )
  )
)

;; Updates artist track list
(define-private (add-track-to-artist (artist principal) (track-id uint))
  (let ((artist-info (default-to {track-ids: (list)} (map-get? artist-tracks {artist: artist}))))
    (map-set artist-tracks
      {artist: artist}
      {track-ids: (unwrap! (as-max-len? (append (get track-ids artist-info) track-id) u100) (err u404))}
    )
  )
)

;; Distributes royalties for a track based on splits
(define-private (distribute-royalties (track-id uint) (amount uint))
  (let (
    (track-info (unwrap! (map-get? tracks {track-id: track-id}) ERR-NOT-FOUND))
    (splits (get royalty-splits track-info))
  )
    ;; For each recipient in splits, calculate their share and transfer
    (map distribute-share splits)
  )
)

;; Helper to calculate and transfer individual royalty share
(define-private (distribute-share (split {recipient: principal, share-percentage: uint}))
  (let (
    (recipient (get recipient split))
    (percentage (get share-percentage split))
    ;; Function would include actual transfer logic in a real implementation
  )
    (print {recipient: recipient, percentage: percentage})
    true
  )
)

;; ===============================================================
;; Read-Only Functions
;; ===============================================================

;; Get track information
(define-read-only (get-track-info (track-id uint))
  (map-get? tracks {track-id: track-id})
)

;; Get all tracks by an artist
(define-read-only (get-artist-tracks (artist principal))
  (let ((artist-info (default-to {track-ids: (list)} (map-get? artist-tracks {artist: artist}))))
    (get track-ids artist-info)
  )
)

;; Get streaming metrics for a track in a specific period
(define-read-only (get-track-metrics (track-id uint) (period uint))
  (default-to {streams: u0} 
    (map-get? streaming-metrics {track-id: track-id, period: period})
  )
)

;; Get platform metrics for a specific period
(define-read-only (get-platform-metrics (period uint))
  (default-to {total-streams: u0, total-revenue: u0} 
    (map-get? platform-metrics {period: period})
  )
)

;; Check subscription status
(define-read-only (get-subscription-status (user principal))
  (let ((subscription (default-to {start-time: u0, end-time: u0, active: false} 
                       (map-get? subscriptions {user: user}))))
    {
      active: (get active subscription),
      remaining-time: (if (> (get end-time subscription) block-height)
                        (- (get end-time subscription) block-height)
                        u0)
    }
  )
)

;; Get current treasury balance
(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

;; Get current accounting period
(define-read-only (get-current-period)
  (var-get current-period)
)

;; ===============================================================
;; Public Functions
;; ===============================================================

;; Register a new music track
(define-public (register-track 
  (title (string-ascii 100)) 
  (metadata-url (string-ascii 255))
  (royalty-splits (list 10 {recipient: principal, share-percentage: uint}))
)
  (let (
    (track-id (var-get next-track-id))
    (current-time block-height)
  )
    ;; Input validation
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (validate-splits royalty-splits) ERR-SPLIT-EXCEEDS-100)
    
    ;; Store track information
    (map-set tracks
      {track-id: track-id}
      {
        title: title,
        artist-address: tx-sender,
        metadata-url: metadata-url,
        registration-time: current-time,
        total-streams: u0,
        royalty-splits: royalty-splits,
        is-active: true
      }
    )
    
    ;; Update artist's track list
    (add-track-to-artist tx-sender track-id)
    
    ;; Increment track ID counter
    (var-set next-track-id (+ track-id u1))
    
    (ok track-id)
  )
)

;; Update track information (only by track owner)
(define-public (update-track 
  (track-id uint) 
  (title (string-ascii 100)) 
  (metadata-url (string-ascii 255))
  (royalty-splits (list 10 {recipient: principal, share-percentage: uint}))
)
  (let ((track-info (unwrap! (map-get? tracks {track-id: track-id}) ERR-NOT-FOUND)))
    ;; Authorization check
    (asserts! (is-eq tx-sender (get artist-address track-info)) ERR-NOT-AUTHORIZED)
    
    ;; Input validation
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (validate-splits royalty-splits) ERR-SPLIT-EXCEEDS-100)
    
    ;; Update track information
    (map-set tracks
      {track-id: track-id}
      (merge track-info {
        title: title,
        metadata-url: metadata-url,
        royalty-splits: royalty-splits
      })
    )
    
    (ok true)
  )
)

;; Record a stream for a track
(define-public (record-stream (track-id uint))
  (let (
    (user tx-sender)
    (period (var-get current-period))
    (track-metrics (default-to {streams: u0} 
                   (map-get? streaming-metrics {track-id: track-id, period: period})))
    (platform-data (default-to {total-streams: u0, total-revenue: u0} 
                   (map-get? platform-metrics {period: period})))
  )
    ;; Ensure track exists
    (asserts! (track-exists track-id) ERR-NOT-FOUND)
    
    ;; Verify user has an active subscription
    (asserts! (is-subscribed user) ERR-NOT-SUBSCRIBED)
    
    ;; Update track streaming metrics
    (map-set streaming-metrics
      {track-id: track-id, period: period}
      {streams: (+ (get streams track-metrics) u1)}
    )
    
    ;; Update track total streams
    (let ((track-info (unwrap! (map-get? tracks {track-id: track-id}) ERR-NOT-FOUND)))
      (map-set tracks
        {track-id: track-id}
        (merge track-info {total-streams: (+ (get total-streams track-info) u1)})
      )
    )
    
    ;; Update platform metrics
    (map-set platform-metrics
      {period: period}
      {
        total-streams: (+ (get total-streams platform-data) u1),
        total-revenue: (get total-revenue platform-data)
      }
    )
    
    (ok true)
  )
)

;; Purchase a subscription
(define-public (subscribe)
  (let (
    (user tx-sender)
    (current-time block-height)
    (subscription (default-to {start-time: u0, end-time: u0, active: false} 
                  (map-get? subscriptions {user: user})))
    (new-end-time (if (and (get active subscription) (> (get end-time subscription) current-time))
                    (+ (get end-time subscription) SUBSCRIPTION-DURATION)
                    (+ current-time SUBSCRIPTION-DURATION)))
  )
    ;; Payment occurs here - collect subscription fee
    (try! (stx-transfer? MONTHLY-SUBSCRIPTION-PRICE tx-sender (as-contract tx-sender)))
    
    ;; Update treasury balance
    (var-set treasury-balance (+ (var-get treasury-balance) MONTHLY-SUBSCRIPTION-PRICE))
    
    ;; Update subscription
    (map-set subscriptions
      {user: user}
      {
        start-time: current-time,
        end-time: new-end-time,
        active: true
      }
    )
    
    ;; Update platform revenue for current period
    (let ((platform-data (default-to {total-streams: u0, total-revenue: u0} 
                         (map-get? platform-metrics {period: (var-get current-period)}))))
      (map-set platform-metrics
        {period: (var-get current-period)}
        {
          total-streams: (get total-streams platform-data),
          total-revenue: (+ (get total-revenue platform-data) MONTHLY-SUBSCRIPTION-PRICE)
        }
      )
    )
    
    (ok {end-time: new-end-time})
  )
)

;; Advance to next accounting period (admin only)
(define-public (advance-period)
  (begin
    ;; Only contract owner can advance the period
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; This would typically include logic to distribute royalties based on streams
    ;; from the previous period before advancing to the next period
    
    ;; Increment period counter
    (var-set current-period (+ (var-get current-period) u1))
    
    (ok (var-get current-period))
  )
)

;; Distribute royalties for the current period (admin only)
(define-public (distribute-period-royalties)
  (begin
    ;; Only contract owner can trigger distribution
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; In a real implementation, this would:
    ;; 1. Calculate each track's share of total streams
    ;; 2. Calculate corresponding revenue allocation
    ;; 3. Distribute to artists according to royalty splits
    ;; 4. Update treasury balance
    
    ;; Placeholder for distribution logic
    (var-set treasury-balance (- (var-get treasury-balance) 
                                (* (var-get treasury-balance) (/ (- u100 PLATFORM-FEE-PERCENT) u100))))
    
    (ok true)
  )
)

;; Deactivate a track (artist only)
(define-public (deactivate-track (track-id uint))
  (let ((track-info (unwrap! (map-get? tracks {track-id: track-id}) ERR-NOT-FOUND)))
    ;; Authorization check
    (asserts! (is-eq tx-sender (get artist-address track-info)) ERR-NOT-AUTHORIZED)
    
    ;; Set track as inactive
    (map-set tracks
      {track-id: track-id}
      (merge track-info {is-active: false})
    )
    
    (ok true)
  )
)

;; Reactivate a track (artist only)
(define-public (reactivate-track (track-id uint))
  (let ((track-info (unwrap! (map-get? tracks {track-id: track-id}) ERR-NOT-FOUND)))
    ;; Authorization check
    (asserts! (is-eq tx-sender (get artist-address track-info)) ERR-NOT-AUTHORIZED)
    
    ;; Set track as active
    (map-set tracks
      {track-id: track-id}
      (merge track-info {is-active: true})
    )
    
    (ok true)
  )
)

;; Withdraw platform fees (admin only)
(define-public (withdraw-platform-fees (amount uint))
  (begin
    ;; Only contract owner can withdraw funds
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Check if treasury has sufficient balance
    (asserts! (<= amount (var-get treasury-balance)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer funds to contract owner
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    
    ;; Update treasury balance
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    
    (ok true)
  )
)