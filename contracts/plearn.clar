;; P2P Learning Platform - Enhanced Version
;; A decentralized quiz platform with STX rewards

;; =============================================================================
;; CONSTANTS & ERROR CODES
;; =============================================================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-ALREADY-SUBMITTED (err u403))
(define-constant ERR-QUIZ-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-VERIFIED (err u410))
(define-constant ERR-NO-SUBMISSION (err u412))
(define-constant ERR-INSUFFICIENT-BALANCE (err u413))
(define-constant ERR-INVALID-REWARD (err u414))
(define-constant ERR-INVALID-TITLE (err u415))
(define-constant ERR-NOT-VERIFIED-OR-CLAIMED (err u421))
(define-constant ERR-ADMIN-ALREADY-EXISTS (err u422))
(define-constant ERR-CANNOT-REMOVE-SELF (err u423))
(define-constant ERR-INVALID-QUIZ-ID (err u424))
(define-constant ERR-ALREADY-INITIALIZED (err u425))
(define-constant ERR-LIST-FULL (err u426))
(define-constant ERR-INVALID-HASH (err u427))
(define-constant ERR-TRANSFER-FAILED (err u428))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-VERIFIED-USERS u100)
(define-constant MIN-REWARD u1000000) ;; 1 STX minimum
(define-constant MAX-REWARD u100000000000) ;; 100,000 STX maximum
(define-constant MAX-QUIZ-ID u1000000) ;; Maximum quiz ID for bounds checking

;; =============================================================================
;; DATA VARIABLES
;; =============================================================================

(define-data-var next-quiz-id uint u1)
(define-data-var contract-balance uint u0)
(define-data-var initialized bool false)

;; =============================================================================
;; DATA MAPS
;; =============================================================================

(define-map quizzes
  uint
  {
    title: (string-ascii 100),
    hash: (buff 32),
    reward: uint,
    creator: principal,
    created-at: uint,
    auto-verify: bool,
    verified-users: (list 100 principal),
    active: bool
  })

(define-map completed
  {quiz-id: uint, user: principal}
  {
    answer-hash: (buff 32),
    submitted-at: uint,
    verified: bool,
    verified-at: (optional uint),
    claimed: bool,
    claimed-at: (optional uint)
  })

(define-map contributors
  principal
  {
    added: bool,
    added-by: principal,
    added-at: uint
  })

(define-map quiz-stats
  uint
  {
    total-submissions: uint,
    total-verified: uint,
    total-claimed: uint
  })

;; =============================================================================
;; INITIALIZATION
;; =============================================================================

(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get initialized)) ERR-ALREADY-INITIALIZED)
    
    ;; Bootstrap contract owner as first admin
    (map-set contributors 
      CONTRACT-OWNER
      {added: true, added-by: CONTRACT-OWNER, added-at: stacks-block-height})
    
    (var-set initialized true)
    (print {event: "contract-initialized", owner: CONTRACT-OWNER})
    (ok true)))

;; =============================================================================
;; PRIVATE FUNCTIONS
;; =============================================================================

(define-private (is-admin (user principal))
  (default-to false (get added (map-get? contributors user))))

(define-private (is-initialized)
  (var-get initialized))

(define-private (validate-quiz-id (quiz-id uint))
  (and (> quiz-id u0) (< quiz-id MAX-QUIZ-ID) (< quiz-id (var-get next-quiz-id))))

(define-private (validate-hash (hash (buff 32)))
  (> (len hash) u0))

(define-private (update-quiz-stats (quiz-id uint) (stat-type (string-ascii 20)))
  (let ((current-stats (default-to 
                         {total-submissions: u0, total-verified: u0, total-claimed: u0}
                         (map-get? quiz-stats quiz-id))))
    (map-set quiz-stats quiz-id
      (if (is-eq stat-type "submission")
          (merge current-stats {total-submissions: (+ (get total-submissions current-stats) u1)})
          (if (is-eq stat-type "verified")
              (merge current-stats {total-verified: (+ (get total-verified current-stats) u1)})
              (if (is-eq stat-type "claimed")
                  (merge current-stats {total-claimed: (+ (get total-claimed current-stats) u1)})
                  current-stats))))))

(define-private (add-user-to-verified-list (quiz-id uint) (user principal))
  (let ((quiz-data (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND))
        (current-users (get verified-users quiz-data)))
    ;; Check if user is already in the list
    (if (is-some (index-of current-users user))
        (ok true) ;; User already in list, no need to add
        ;; Try to add user to the list
        (let ((new-list (unwrap! (as-max-len? (append current-users user) u100) ERR-LIST-FULL)))
          (map-set quizzes quiz-id
            (merge quiz-data {verified-users: new-list}))
          (ok true)))))

;; =============================================================================
;; ADMIN FUNCTIONS
;; =============================================================================

(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-admin new-admin)) ERR-ADMIN-ALREADY-EXISTS)
    (map-set contributors 
      new-admin
      {added: true, added-by: tx-sender, added-at: stacks-block-height})
    (print {event: "admin-added", admin: new-admin, added-by: tx-sender})
    (ok true)))

(define-public (remove-admin (admin principal))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq admin tx-sender)) ERR-CANNOT-REMOVE-SELF)
    (asserts! (is-admin admin) ERR-NOT-AUTHORIZED)
    (map-delete contributors admin)
    (print {event: "admin-removed", admin: admin, removed-by: tx-sender})
    (ok true)))

;; =============================================================================
;; QUIZ MANAGEMENT
;; =============================================================================

(define-public (add-quiz (title (string-ascii 100)) (answer-hash (buff 32)) (reward uint) (auto-verify bool))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (validate-hash answer-hash) ERR-INVALID-HASH)
    (asserts! (and (>= reward MIN-REWARD) (<= reward MAX-REWARD)) ERR-INVALID-REWARD)
    
    (let ((id (var-get next-quiz-id)))
      (asserts! (< id MAX-QUIZ-ID) ERR-INVALID-QUIZ-ID)
      
      (map-set quizzes
        id
        {
          title: title,
          hash: answer-hash,
          reward: reward,
          creator: tx-sender,
          created-at: stacks-block-height,
          auto-verify: auto-verify,
          verified-users: (list),
          active: true
        })
      
      ;; Initialize stats
      (map-set quiz-stats id
        {total-submissions: u0, total-verified: u0, total-claimed: u0})
      
      (var-set next-quiz-id (+ id u1))
      (print {event: "quiz-created", quiz-id: id, title: title, reward: reward, creator: tx-sender})
      (ok id))))

(define-public (deactivate-quiz (quiz-id uint))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (validate-quiz-id quiz-id) ERR-INVALID-QUIZ-ID)
    
    (let ((quiz-data (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND)))
      (map-set quizzes quiz-id
        (merge quiz-data {active: false}))
      (print {event: "quiz-deactivated", quiz-id: quiz-id, deactivated-by: tx-sender})
      (ok true))))

;; =============================================================================
;; USER FUNCTIONS
;; =============================================================================

(define-public (submit-answer (quiz-id uint) (answer-hash (buff 32)))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (validate-quiz-id quiz-id) ERR-INVALID-QUIZ-ID)
    (asserts! (validate-hash answer-hash) ERR-INVALID-HASH)
    
    ;; Check if quiz exists and is active
    (let ((quiz-data (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND)))
      (asserts! (get active quiz-data) ERR-QUIZ-NOT-FOUND)
      
      ;; Check if already submitted
      (asserts! (is-none (map-get? completed {quiz-id: quiz-id, user: tx-sender})) 
                ERR-ALREADY-SUBMITTED)
      
      (let ((is-correct (and (get auto-verify quiz-data) (is-eq answer-hash (get hash quiz-data)))))
        ;; Store submission
        (map-set completed {quiz-id: quiz-id, user: tx-sender}
          {
            answer-hash: answer-hash,
            submitted-at: stacks-block-height,
            verified: is-correct,
            verified-at: (if is-correct (some stacks-block-height) none),
            claimed: false,
            claimed-at: none
          })
        
        ;; Update stats
        (update-quiz-stats quiz-id "submission")
        
        ;; If auto-verify and correct answer, update verified stats and quiz
        (if is-correct
            (begin
              (update-quiz-stats quiz-id "verified")
              (try! (add-user-to-verified-list quiz-id tx-sender))
              (print {event: "answer-auto-verified", quiz-id: quiz-id, user: tx-sender}))
            (print {event: "answer-submitted", quiz-id: quiz-id, user: tx-sender}))
        
        (ok true)))))

(define-public (verify-answer (quiz-id uint) (user principal))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (validate-quiz-id quiz-id) ERR-INVALID-QUIZ-ID)
    
    (let ((entry (unwrap! (map-get? completed {quiz-id: quiz-id, user: user}) ERR-NO-SUBMISSION)))
      (asserts! (not (get verified entry)) ERR-ALREADY-VERIFIED)
      
      ;; Update completion record
      (map-set completed {quiz-id: quiz-id, user: user}
        (merge entry {verified: true, verified-at: (some stacks-block-height)}))
      
      ;; Add to verified users list
      (try! (add-user-to-verified-list quiz-id user))
      (update-quiz-stats quiz-id "verified")
      (print {event: "answer-verified", quiz-id: quiz-id, user: user, verified-by: tx-sender})
      (ok true))))

(define-public (claim-reward (quiz-id uint))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (validate-quiz-id quiz-id) ERR-INVALID-QUIZ-ID)
    
    (let ((entry (unwrap! (map-get? completed {quiz-id: quiz-id, user: tx-sender}) ERR-NOT-VERIFIED-OR-CLAIMED))
          (quiz-data (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND)))
      
      (asserts! (and (get verified entry) (not (get claimed entry))) 
                ERR-NOT-VERIFIED-OR-CLAIMED)
      
      (let ((amount (get reward quiz-data)))
        ;; Check contract has sufficient balance
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Transfer reward from contract to user
        (unwrap! (as-contract (stx-transfer? amount tx-sender tx-sender)) ERR-TRANSFER-FAILED)
        
        ;; Mark as claimed
        (map-set completed {quiz-id: quiz-id, user: tx-sender}
          (merge entry {claimed: true, claimed-at: (some stacks-block-height)}))
        
        (update-quiz-stats quiz-id "claimed")
        (print {event: "reward-claimed", quiz-id: quiz-id, user: tx-sender, amount: amount})
        (ok amount)))))

;; =============================================================================
;; CONTRACT FUNDING
;; =============================================================================

(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-initialized) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-REWARD)
    
    (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) ERR-TRANSFER-FAILED)
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (print {event: "contract-funded", amount: amount, funder: tx-sender})
    (ok true)))

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-quiz (quiz-id uint))
  (if (validate-quiz-id quiz-id)
      (match (map-get? quizzes quiz-id)
        quiz (ok quiz)
        ERR-QUIZ-NOT-FOUND)
      ERR-INVALID-QUIZ-ID))

(define-read-only (get-quiz-public-info (quiz-id uint))
  (if (validate-quiz-id quiz-id)
      (match (map-get? quizzes quiz-id)
        quiz (ok {
          title: (get title quiz),
          reward: (get reward quiz),
          creator: (get creator quiz),
          created-at: (get created-at quiz),
          active: (get active quiz),
          verified-count: (len (get verified-users quiz))
        })
        ERR-QUIZ-NOT-FOUND)
      ERR-INVALID-QUIZ-ID))

(define-read-only (get-user-status (quiz-id uint) (user principal))
  (if (validate-quiz-id quiz-id)
      (match (map-get? completed {quiz-id: quiz-id, user: user})
        status (ok status)
        (ok {answer-hash: 0x, submitted-at: u0, verified: false, verified-at: none, claimed: false, claimed-at: none}))
      ERR-INVALID-QUIZ-ID))

(define-read-only (get-quiz-stats (quiz-id uint))
  (if (validate-quiz-id quiz-id)
      (match (map-get? quiz-stats quiz-id)
        stats (ok stats)
        (ok {total-submissions: u0, total-verified: u0, total-claimed: u0}))
      ERR-INVALID-QUIZ-ID))

(define-read-only (is-user-admin (user principal))
  (is-admin user))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

(define-read-only (get-next-quiz-id)
  (var-get next-quiz-id))

(define-read-only (is-contract-initialized)
  (var-get initialized))

;; Get list of verified users for a quiz
(define-read-only (get-verified-users (quiz-id uint))
  (if (validate-quiz-id quiz-id)
      (match (map-get? quizzes quiz-id)
        quiz (ok (get verified-users quiz))
        ERR-QUIZ-NOT-FOUND)
      ERR-INVALID-QUIZ-ID))

;; Simple quiz listing for frontend
(define-read-only (get-quiz-count)
  (- (var-get next-quiz-id) u1))