;; NFT Marketplace Listing Contract
;; Purpose: Manage NFT listings on a decentralized marketplace

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INVALID-PRICE (err u400))
(define-constant ERR-ALREADY-LISTED (err u409))
(define-constant ERR-NOT-LISTED (err u410))
(define-constant ERR-NOT-OWNER (err u403))
(define-constant ERR-INVALID-NFT (err u411))

;; Data Structures
;; Listing details map: nft-id -> listing-info
(define-map listings
  { nft-id: uint, collection: principal }
  {
    seller: principal,
    price: uint,
    listed-at: uint,
    updated-at: uint
  }
)

;; Track all active listings for a seller
(define-map seller-listings
  { seller: principal }
  { listing-ids: (list 100 { nft-id: uint, collection: principal }) }
)

;; Track listing count for pagination
(define-data-var total-listings uint u0)

;; Events (using print for event emission)
(define-private (emit-list-event (nft-id uint) (collection principal) (seller principal) (price uint))
  (print {
    event: "nft-listed",
    nft-id: nft-id,
    collection: collection,
    seller: seller,
    price: price,
    timestamp: block-height
  })
)

(define-private (emit-delist-event (nft-id uint) (collection principal) (seller principal))
  (print {
    event: "nft-delisted",
    nft-id: nft-id,
    collection: collection,
    seller: seller,
    timestamp: block-height
  })
)

(define-private (emit-update-event (nft-id uint) (collection principal) (seller principal) (new-price uint))
  (print {
    event: "listing-updated",
    nft-id: nft-id,
    collection: collection,
    seller: seller,
    new-price: new-price,
    timestamp: block-height
  })
)

;; Helper function to verify NFT ownership
;; This is a placeholder - integrate with your actual NFT contract
(define-private (verify-nft-ownership (nft-id uint) (collection principal) (owner principal))
  ;; In production, this would call the actual NFT contract to verify ownership
  ;; For now, we assume the caller is the owner
  ;; Example: (contract-call? collection is-owner nft-id owner)
  true
)

;; List an NFT for sale
;; @param nft-id: The ID of the NFT to list
;; @param collection: The principal of the NFT collection contract
;; @param price: The listing price in microSTX
;; @returns: ok with listing details or error
(define-public (list-nft (nft-id uint) (collection principal) (price uint))
  (let (
    (seller tx-sender)
    (listing-key { nft-id: nft-id, collection: collection })
  )
    ;; Validate price
    (asserts! (> price u0) ERR-INVALID-PRICE)
    
    ;; Check if already listed
    (asserts! (is-none (map-get? listings listing-key)) ERR-ALREADY-LISTED)
    
    ;; Verify ownership
    (asserts! (verify-nft-ownership nft-id collection seller) ERR-NOT-OWNER)
    
    ;; Create listing
    (map-set listings
      listing-key
      {
        seller: seller,
        price: price,
        listed-at: block-height,
        updated-at: block-height
      }
    )
    
    ;; Update seller's listings
    (let (
      (current-listings (default-to { listing-ids: (list) } (map-get? seller-listings { seller: seller })))
    )
      (map-set seller-listings
        { seller: seller }
        {
          listing-ids: (unwrap! (as-max-len? (append (get listing-ids current-listings) listing-key) u100) ERR-INVALID-NFT)
        }
      )
    )
    
    ;; Increment total listings
    (var-set total-listings (+ (var-get total-listings) u1))
    
    ;; Emit event
    (emit-list-event nft-id collection seller price)
    
    ;; Return success
    (ok {
      nft-id: nft-id,
      collection: collection,
      seller: seller,
      price: price,
      listed-at: block-height
    })
  )
)

;; Delist an NFT from the marketplace
;; @param nft-id: The ID of the NFT to delist
;; @param collection: The principal of the NFT collection contract
;; @returns: ok or error
(define-public (delist-nft (nft-id uint) (collection principal))
  (let (
    (seller tx-sender)
    (listing-key { nft-id: nft-id, collection: collection })
    (listing (map-get? listings listing-key))
  )
    ;; Check if listing exists
    (asserts! (is-some listing) ERR-NOT-LISTED)
    
    ;; Verify caller is the seller
    (asserts! (is-eq seller (get seller (unwrap! listing ERR-NOT-LISTED))) ERR-NOT-OWNER)
    
    ;; Remove listing
    (map-delete listings listing-key)
    
    ;; Update seller's listings
    (let (
      (current-listings (default-to { listing-ids: (list) } (map-get? seller-listings { seller: seller })))
      ;; Replace filter with fold to properly iterate and rebuild the list without the delisted NFT
      (updated-ids (fold remove-listing-from-list (get listing-ids current-listings) { nft-id: nft-id, collection: collection, result: (list) }))
    )
      (if (> (len (get result updated-ids)) u0)
        (map-set seller-listings { seller: seller } { listing-ids: (get result updated-ids) })
        (map-delete seller-listings { seller: seller })
      )
    )
    
    ;; Decrement total listings
    (var-set total-listings (- (var-get total-listings) u1))
    
    ;; Emit event
    (emit-delist-event nft-id collection seller)
    
    ;; Return success
    (ok true)
  )
)

;; Helper function for fold to remove a specific listing from the list
(define-private (remove-listing-from-list (item { nft-id: uint, collection: principal }) (acc { nft-id: uint, collection: principal, result: (list 100 { nft-id: uint, collection: principal }) }))
  (if (or (not (is-eq (get nft-id item) (get nft-id acc))) (not (is-eq (get collection item) (get collection acc))))
    { nft-id: (get nft-id acc), collection: (get collection acc), result: (unwrap! (as-max-len? (append (get result acc) item) u100) acc) }
    acc
  )
)


;; Get listing details
;; @param nft-id: The ID of the NFT
;; @param collection: The principal of the NFT collection contract
;; @returns: ok with listing details or error
(define-read-only (get-listing (nft-id uint) (collection principal))
  (let (
    (listing-key { nft-id: nft-id, collection: collection })
    (listing (map-get? listings listing-key))
  )
    (match listing
      listing-data (ok listing-data)
      ERR-NOT-FOUND
    )
  )
)

;; Update listing price or details
;; @param nft-id: The ID of the NFT
;; @param collection: The principal of the NFT collection contract
;; @param new-price: The new price for the listing
;; @returns: ok with updated listing or error
(define-public (update-listing (nft-id uint) (collection principal) (new-price uint))
  (let (
    (seller tx-sender)
    (listing-key { nft-id: nft-id, collection: collection })
    (listing (map-get? listings listing-key))
  )
    ;; Validate new price
    (asserts! (> new-price u0) ERR-INVALID-PRICE)
    
    ;; Check if listing exists
    (asserts! (is-some listing) ERR-NOT-LISTED)
    
    ;; Verify caller is the seller
    (asserts! (is-eq seller (get seller (unwrap! listing ERR-NOT-LISTED))) ERR-NOT-OWNER)
    
    ;; Update listing
    (map-set listings
      listing-key
      {
        seller: seller,
        price: new-price,
        listed-at: (get listed-at (unwrap! listing ERR-NOT-LISTED)),
        updated-at: block-height
      }
    )
    
    ;; Emit event
    (emit-update-event nft-id collection seller new-price)
    
    ;; Return success
    (ok {
      nft-id: nft-id,
      collection: collection,
      seller: seller,
      price: new-price,
      updated-at: block-height
    })
  )
)

;; Get all listings for a seller
;; @param seller: The principal of the seller
;; @returns: ok with list of listings or error
(define-read-only (get-seller-listings (seller principal))
  (match (map-get? seller-listings { seller: seller })
    listings-data (ok (get listing-ids listings-data))
    (ok (list))
  )
)

;; Get total number of active listings
;; @returns: total listings count
(define-read-only (get-total-listings)
  (var-get total-listings)
)

;; Check if an NFT is listed
;; @param nft-id: The ID of the NFT
;; @param collection: The principal of the NFT collection contract
;; @returns: true if listed, false otherwise
(define-read-only (is-listed (nft-id uint) (collection principal))
  (is-some (map-get? listings { nft-id: nft-id, collection: collection }))
)