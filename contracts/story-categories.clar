;; Story Categories and Tags Contract
;; Provides categorization and tagging system for Newspad stories

(define-constant MAX_TAGS u10)
(define-constant MAX_STORIES_PER_INDEX u1000)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INACTIVE (err u103))
(define-constant ERR_LIMIT (err u104))

(define-data-var admin principal tx-sender)
(define-data-var newspad principal tx-sender)
(define-data-var category-counter uint u0)

;; Category definitions
(define-map categories { id: uint } { name: (string-ascii 32), active: bool })
(define-map category-names { name: (string-ascii 32) } { id: uint })

;; Story categorization and tagging
(define-map story-categories { story-id: uint } { category-id: uint })
(define-map story-tags { story-id: uint } { tags: (list 10 (string-ascii 32)) })

;; Indexes for browsing
(define-map category-stories { category-id: uint } { stories: (list 1000 uint) })
(define-map tag-stories { tag: (string-ascii 32) } { stories: (list 1000 uint) })

;; Access control helpers
;; (define-private (only-admin)
  ;; (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED))

;; (define-private (only-newspad)
  ;; (asserts! (is-eq tx-sender (var-get newspad)) ERR_UNAUTHORIZED))

;; Admin functions
(define-public (set-newspad (principal principal))
  (begin
    ;; (try! (only-admin))
    (var-set newspad principal)
    (ok true)))

(define-public (create-category (name (string-ascii 32)))
  (begin
    ;; (try! (only-admin))
    (asserts! (is-none (map-get? category-names { name: name })) ERR_EXISTS)
    (let ((id (+ (var-get category-counter) u1)))
      (map-set categories { id: id } { name: name, active: true })
      (map-set category-names { name: name } { id: id })
      (var-set category-counter id)
      (ok id))))

(define-public (set-category-status (id uint) (active bool))
  (begin
    ;; (try! (only-admin))
    (match (map-get? categories { id: id })
      category (begin
        (map-set categories { id: id } { name: (get name category), active: active })
        (ok true))
      ERR_NOT_FOUND)))

;; Newspad-only functions
(define-public (set-story-category (story-id uint) (category-id uint))
  (begin
    ;; (try! (only-newspad))
    (asserts! (is-none (map-get? story-categories { story-id: story-id })) ERR_EXISTS)
    (match (map-get? categories { id: category-id })
      category (begin
        (asserts! (get active category) ERR_INACTIVE)
        (let ((current-stories (default-to (list) 
          (get stories (map-get? category-stories { category-id: category-id })))))
          (asserts! (< (len current-stories) MAX_STORIES_PER_INDEX) ERR_LIMIT)
          (map-set story-categories { story-id: story-id } { category-id: category-id })
          (map-set category-stories { category-id: category-id } 
            { stories: (unwrap-panic (as-max-len? (append current-stories story-id) u1000)) })
          (ok true)))
      ERR_NOT_FOUND)))

(define-public (add-tag (story-id uint) (tag (string-ascii 32)))
  (begin
    ;; (try! (only-newspad))
    (let ((current-tags (default-to (list) (get tags (map-get? story-tags { story-id: story-id })))))
      (asserts! (< (len current-tags) MAX_TAGS) ERR_LIMIT)
      (let ((new-tags (unwrap-panic (as-max-len? (append current-tags tag) u10))))
        (map-set story-tags { story-id: story-id } { tags: new-tags })
        (let ((tag-story-list (default-to (list) 
          (get stories (map-get? tag-stories { tag: tag })))))
          (asserts! (< (len tag-story-list) MAX_STORIES_PER_INDEX) ERR_LIMIT)
          (map-set tag-stories { tag: tag } 
            { stories: (unwrap-panic (as-max-len? (append tag-story-list story-id) u1000)) })
          (ok true))))))

;; Read-only functions
(define-read-only (get-category (id uint))
  (map-get? categories { id: id }))

(define-read-only (get-category-by-name (name (string-ascii 32)))
  (match (map-get? category-names { name: name })
    name-entry (map-get? categories { id: (get id name-entry) })
    none))

(define-read-only (get-category-id-by-name (name (string-ascii 32)))
  (map-get? category-names { name: name }))

(define-read-only (get-story-category (story-id uint))
  (map-get? story-categories { story-id: story-id }))

(define-read-only (get-story-tags (story-id uint))
  (default-to (list) (get tags (map-get? story-tags { story-id: story-id }))))

(define-read-only (get-stories-by-category (category-id uint))
  (default-to (list) (get stories (map-get? category-stories { category-id: category-id }))))

(define-read-only (get-stories-by-tag (tag (string-ascii 32)))
  (default-to (list) (get stories (map-get? tag-stories { tag: tag }))))

(define-read-only (get-category-counter)
  (var-get category-counter))

;; Helper functions for checking system state
(define-read-only (is-category-active (id uint))
  (match (map-get? categories { id: id })
    category (get active category)
    false))

(define-read-only (has-story-category (story-id uint))
  (is-some (map-get? story-categories { story-id: story-id })))

(define-read-only (get-story-tag-count (story-id uint))
  (len (get-story-tags story-id)))