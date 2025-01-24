;; DreamLauncher: Phase-based Project Funding Contract
;; Description: A decentralized platform for launching creative projects with phase validation

;; Constants
(define-constant CONTRACT_ADMIN tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROJECT (err u101))
(define-constant ERR_PROJECT_EXISTS (err u102))
(define-constant ERR_NO_FUNDS (err u103))
(define-constant ERR_PHASE_NOT_FOUND (err u104))
(define-constant ERR_INVALID_PHASE_STATUS (err u105))
(define-constant ERR_PROJECT_CLOSED (err u106))
(define-constant ERR_FUNDS_CLAIMED (err u107))
(define-constant ERR_BAD_INPUT (err u108))

;; Data Types
(define-map projects
    { project-id: uint }
    {
        initiator: principal,
        name: (string-ascii 64),
        overview: (string-ascii 256),
        target-amount: uint,
        close-block: uint,
        current-funds: uint,
        status-active: bool,
        released-funds: uint
    }
)

(define-map phases
    { project-id: uint, phase-id: uint }
    {
        overview: (string-ascii 256),
        budget: uint,
        target-date: uint,
        status-complete: bool,
        required-approvals: uint,
        current-approvals: uint,
        budget-released: bool
    }
)

(define-map project-backers
    { project-id: uint, backer: principal }
    { contribution: uint }
)

(define-map phase-approvals
    { project-id: uint, phase-id: uint, approver: principal }
    { approved: bool }
)

;; Project Counter
(define-data-var project-counter uint u0)

;; Helper Functions
(define-private (check-text-input (input (string-ascii 256)))
    (> (len input) u0)
)

(define-private (check-number-input (input uint))
    (> input u0)
)

(define-private (check-project-exists (project-id uint))
    (is-some (map-get? projects { project-id: project-id }))
)

(define-private (check-phase-exists (project-id uint) (phase-id uint))
    (is-some (map-get? phases { project-id: project-id, phase-id: phase-id }))
)

;; Administrative Functions
(define-public (launch-project (name (string-ascii 64)) 
                             (overview (string-ascii 256))
                             (target-amount uint)
                             (duration uint))
    (let
        (
            (new-id (+ (var-get project-counter) u1))
            (close-block (+ block-height duration))
        )
        (asserts! (check-text-input name) ERR_BAD_INPUT)
        (asserts! (check-text-input overview) ERR_BAD_INPUT)
        (asserts! (check-number-input target-amount) ERR_BAD_INPUT)
        (asserts! (check-number-input duration) ERR_BAD_INPUT)
        
        (map-set projects
            { project-id: new-id }
            {
                initiator: tx-sender,
                name: name,
                overview: overview,
                target-amount: target-amount,
                close-block: close-block,
                current-funds: u0,
                status-active: true,
                released-funds: u0
            }
        )
        
        (var-set project-counter new-id)
        (ok new-id)
    )
)

(define-public (create-phase (project-id uint)
                           (overview (string-ascii 256))
                           (budget uint)
                           (target-date uint)
                           (required-approvals uint))
    (let
        (
            (project (unwrap! (map-get? projects { project-id: project-id }) ERR_INVALID_PROJECT))
        )
        (asserts! (check-project-exists project-id) ERR_INVALID_PROJECT)
        (asserts! (check-text-input overview) ERR_BAD_INPUT)
        (asserts! (check-number-input budget) ERR_BAD_INPUT)
        (asserts! (check-number-input target-date) ERR_BAD_INPUT)
        (asserts! (check-number-input required-approvals) ERR_BAD_INPUT)
        (asserts! (is-eq (get initiator project) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get status-active project) ERR_PROJECT_CLOSED)
        
        (map-set phases
            { project-id: project-id, phase-id: u0 }
            {
                overview: overview,
                budget: budget,
                target-date: target-date,
                status-complete: false,
                required-approvals: required-approvals,
                current-approvals: u0,
                budget-released: false
            }
        )
        (ok true)
    )
)

;; Funding Functions
(define-public (back-project (project-id uint) (amount uint))
    (let
        (
            (project (unwrap! (map-get? projects { project-id: project-id }) ERR_INVALID_PROJECT))
            (previous-amount (default-to u0 (get contribution (map-get? project-backers { project-id: project-id, backer: tx-sender }))))
        )
        (asserts! (check-project-exists project-id) ERR_INVALID_PROJECT)
        (asserts! (check-number-input amount) ERR_BAD_INPUT)
        (asserts! (get status-active project) ERR_PROJECT_CLOSED)
        (asserts! (<= block-height (get close-block project)) ERR_PROJECT_CLOSED)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set projects
            { project-id: project-id }
            (merge project { current-funds: (+ (get current-funds project) amount) })
        )
        
        (map-set project-backers
            { project-id: project-id, backer: tx-sender }
            { contribution: (+ previous-amount amount) }
        )
        
        (ok true)
    )
)

;; Phase Fund Release
(define-public (release-phase-funds (project-id uint) (phase-id uint))
    (let
        (
            (project (unwrap! (map-get? projects { project-id: project-id }) ERR_INVALID_PROJECT))
            (phase (unwrap! (map-get? phases { project-id: project-id, phase-id: phase-id }) ERR_PHASE_NOT_FOUND))
        )
        (asserts! (check-project-exists project-id) ERR_INVALID_PROJECT)
        (asserts! (check-phase-exists project-id phase-id) ERR_PHASE_NOT_FOUND)
        (asserts! (is-eq (get initiator project) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get status-complete phase) ERR_INVALID_PHASE_STATUS)
        (asserts! (not (get budget-released phase)) ERR_FUNDS_CLAIMED)
        
        (let
            (
                (release-amount (get budget phase))
                (new-released (+ (get released-funds project) release-amount))
            )
            (asserts! (<= new-released (get current-funds project)) ERR_NO_FUNDS)
            
            (try! (as-contract (stx-transfer? release-amount tx-sender (get initiator project))))
            
            (map-set phases
                { project-id: project-id, phase-id: phase-id }
                (merge phase { budget-released: true })
            )
            
            (map-set projects
                { project-id: project-id }
                (merge project { released-funds: new-released })
            )
            
            (ok release-amount)
        )
    )
)

;; Phase Approval System
(define-public (approve-phase (project-id uint) (phase-id uint))
    (let
        (
            (phase (unwrap! (map-get? phases { project-id: project-id, phase-id: phase-id }) ERR_PHASE_NOT_FOUND))
            (project (unwrap! (map-get? projects { project-id: project-id }) ERR_INVALID_PROJECT))
            (is-backer (> (default-to u0 (get contribution (map-get? project-backers { project-id: project-id, backer: tx-sender }))) u0))
        )
        (asserts! (check-project-exists project-id) ERR_INVALID_PROJECT)
        (asserts! (check-phase-exists project-id phase-id) ERR_PHASE_NOT_FOUND)
        (asserts! is-backer ERR_UNAUTHORIZED)
        (asserts! (not (get status-complete phase)) ERR_INVALID_PHASE_STATUS)
        (asserts! (not (default-to false (get approved (map-get? phase-approvals { project-id: project-id, phase-id: phase-id, approver: tx-sender })))) ERR_UNAUTHORIZED)
        
        (map-set phase-approvals
            { project-id: project-id, phase-id: phase-id, approver: tx-sender }
            { approved: true }
        )
        
        (map-set phases
            { project-id: project-id, phase-id: phase-id }
            (merge phase { current-approvals: (+ (get current-approvals phase) u1) })
        )
        
        (if (>= (+ (get current-approvals phase) u1) (get required-approvals phase))
            (begin
                (map-set phases
                    { project-id: project-id, phase-id: phase-id }
                    (merge phase { 
                        status-complete: true,
                        current-approvals: (+ (get current-approvals phase) u1)
                    })
                )
                (ok true)
            )
            (ok true)
        )
    )
)

;; Refund System
(define-public (request-refund (project-id uint))
    (let
        (
            (project (unwrap! (map-get? projects { project-id: project-id }) ERR_INVALID_PROJECT))
            (backer-amount (unwrap! (get contribution (map-get? project-backers { project-id: project-id, backer: tx-sender })) ERR_NO_FUNDS))
        )
        (asserts! (check-project-exists project-id) ERR_INVALID_PROJECT)
        (asserts! (> block-height (get close-block project)) ERR_INVALID_PROJECT)
        (asserts! (< (get current-funds project) (get target-amount project)) ERR_INVALID_PROJECT)
        
        (try! (as-contract (stx-transfer? backer-amount tx-sender tx-sender)))
        
        (map-delete project-backers { project-id: project-id, backer: tx-sender })
        
        (map-set projects
            { project-id: project-id }
            (merge project { current-funds: (- (get current-funds project) backer-amount) })
        )
        
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-project-details (project-id uint))
    (map-get? projects { project-id: project-id })
)

(define-read-only (get-phase-details (project-id uint) (phase-id uint))
    (map-get? phases { project-id: project-id, phase-id: phase-id })
)

(define-read-only (get-backer-contribution (project-id uint) (backer principal))
    (map-get? project-backers { project-id: project-id, backer: backer })
)