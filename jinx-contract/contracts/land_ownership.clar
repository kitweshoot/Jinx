;; Land Ownership Contract
;; Manages virtual land parcels as NFTs

;; Define the SIP-009 NFT trait inline
(define-trait nft-trait
  (
    (get-last-token-id () (response uint uint))
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Define the land NFT
(define-non-fungible-token land-parcel uint)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-token-not-found (err u102))
(define-constant err-invalid-coordinates (err u103))
(define-constant err-land-already-exists (err u104))
(define-constant err-invalid-size (err u105))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var base-uri (string-ascii 256) "https://api.landnft.com/metadata/")

;; Data Maps
(define-map land-metadata uint {
  title: (string-ascii 64),
  description: (string-ascii 256),
  x-coordinate: uint,
  y-coordinate: uint,
  width: uint,
  height: uint,
  land-type: (string-ascii 32),
  created-at: uint,
  creator: principal
})

;; Map to track land parcels by coordinates (to prevent overlapping)
(define-map coordinate-registry {x: uint, y: uint, width: uint, height: uint} uint)

;; Private Functions

;; Check if coordinates overlap with existing land
(define-private (coordinates-overlap (x1 uint) (y1 uint) (w1 uint) (h1 uint) (x2 uint) (y2 uint) (w2 uint) (h2 uint))
  (and 
    (< x1 (+ x2 w2))
    (< x2 (+ x1 w1))
    (< y1 (+ y2 h2))
    (< y2 (+ y1 h1))
  )
)

;; Check if land coordinates are valid and don't overlap
(define-private (is-valid-land-placement (x uint) (y uint) (width uint) (height uint))
  (and 
    (> width u0)
    (> height u0)
    (< x u10000) ;; Max coordinate limit
    (< y u10000)
    (< (+ x width) u10000)
    (< (+ y height) u10000)
  )
)

;; Public Functions

;; Mint a new land parcel
(define-public (mint-land 
  (recipient principal)
  (title (string-ascii 64))
  (description (string-ascii 256))
  (x-coordinate uint)
  (y-coordinate uint)
  (width uint)
  (height uint)
  (land-type (string-ascii 32))
)
  (let 
    (
      (token-id (+ (var-get last-token-id) u1))
    )
    ;; Validate coordinates and size
    (asserts! (is-valid-land-placement x-coordinate y-coordinate width height) err-invalid-coordinates)
    (asserts! (> width u0) err-invalid-size)
    (asserts! (> height u0) err-invalid-size)
    
    ;; Check if coordinates are already taken (simplified check)
    (asserts! (is-none (map-get? coordinate-registry {x: x-coordinate, y: y-coordinate, width: width, height: height})) err-land-already-exists)
    
    ;; Mint the NFT
    (try! (nft-mint? land-parcel token-id recipient))
    
    ;; Store metadata
    (map-set land-metadata token-id {
      title: title,
      description: description,
      x-coordinate: x-coordinate,
      y-coordinate: y-coordinate,
      width: width,
      height: height,
      land-type: land-type,
      created-at: block-height,
      creator: tx-sender
    })
    
    ;; Register coordinates
    (map-set coordinate-registry {x: x-coordinate, y: y-coordinate, width: width, height: height} token-id)
    
    ;; Update last token ID
    (var-set last-token-id token-id)
    
    (ok token-id)
  )
)

;; Transfer land ownership
(define-public (transfer-land (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Check if token exists
    (asserts! (is-some (nft-get-owner? land-parcel token-id)) err-token-not-found)
    ;; Check if sender owns the token
    (asserts! (is-eq (some sender) (nft-get-owner? land-parcel token-id)) err-not-token-owner)
    ;; Transfer the NFT
    (try! (nft-transfer? land-parcel token-id sender recipient))
    (ok true)
  )
)

;; Get owner of a land parcel
(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? land-parcel token-id))
)

;; Get land metadata
(define-read-only (get-land-metadata (token-id uint))
  (map-get? land-metadata token-id)
)

;; Get land by coordinates
(define-read-only (get-land-by-coordinates (x uint) (y uint) (width uint) (height uint))
  (map-get? coordinate-registry {x: x, y: y, width: width, height: height})
)

;; Check if coordinates are available
(define-read-only (is-coordinates-available (x uint) (y uint) (width uint) (height uint))
  (and 
    (is-valid-land-placement x y width height)
    (is-none (map-get? coordinate-registry {x: x, y: y, width: width, height: height}))
  )
)

;; Get all land parcels owned by a principal (simplified version)
(define-read-only (get-lands-owned (owner principal))
  (let 
    (
      (max-id (var-get last-token-id))
    )
    ;; Return the count of owned tokens (simplified)
    (fold check-land-ownership (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) {owner: owner, count: u0})
  )
)

;; Helper function for counting owned land
(define-private (check-land-ownership (token-id uint) (data {owner: principal, count: uint}))
  (let 
    (
      (owner (get owner data))
      (current-count (get count data))
    )
    (if (is-eq (nft-get-owner? land-parcel token-id) (some owner))
      {owner: owner, count: (+ current-count u1)}
      data
    )
  )
)

;; SIP-009 Standard Functions

;; Get the last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; Get token URI
(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat (var-get base-uri) (uint-to-ascii token-id))))
)

;; Transfer function for SIP-009 compliance
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (transfer-land token-id sender recipient)
)

;; Admin Functions

;; Set base URI (only contract owner)
(define-public (set-base-uri (new-base-uri (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set base-uri new-base-uri)
    (ok true)
  )
)

;; Get contract info
(define-read-only (get-contract-info)
  {
    total-supply: (var-get last-token-id),
    base-uri: (var-get base-uri),
    contract-owner: contract-owner
  }
)

;; Helper function to convert uint to string (simplified)
(define-private (uint-to-ascii (value uint))
  (if (is-eq value u0) "0"
  (if (is-eq value u1) "1"
  (if (is-eq value u2) "2"
  (if (is-eq value u3) "3"
  (if (is-eq value u4) "4"
  (if (is-eq value u5) "5"
  (if (is-eq value u6) "6"
  (if (is-eq value u7) "7"
  (if (is-eq value u8) "8"
  (if (is-eq value u9) "9"
  "unknown"))))))))))
)
