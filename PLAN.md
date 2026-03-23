# Smart Credential Insights + Optimal Password-Phased Dual Run

## Part 1: Smart Credential Insights Card on Dashboard

**Features:**

- New "Intel" card on the Dashboard between the quick actions and category gauges
- Shows at-a-glance operational intelligence pulled from credentials, exclusion lists, and past run data
- Displays: untested credentials count, temp-disabled (confirmed accounts) count, perm-excluded count, no-account excluded count, and "next run will process X" prediction
- Each insight row is tappable — e.g. tapping "12 Temp Disabled" jumps straight to the Credentials tab filtered to those
- Shows a "readiness score" — a simple fraction like "Ready: 47/120" meaning 47 credentials are eligible for the next run out of 120 total
- Color-coded: green for actionable items, orange for warnings (e.g. "0 untested left"), red for blockers

**Design:**

- Neon-themed card matching the existing dashboard style
- Compact 2-column grid of insight pills with icon + count + label
- A top-line readiness bar showing eligible vs total credentials
- Subtle pulse animation on the readiness count when it changes

---

## Part 2: Optimal Password-Phased Dual Run — Minimum Possible Clicks

The automation engine now uses the mathematically optimal ordering strategy for testing 3 passwords across all emails. Instead of testing all passwords per email sequentially (wasteful), it phases passwords globally to minimize total site interactions.

**Core Strategy (Minimum Clicks):**

- **Phase 1**: Test Password 1 for ALL emails simultaneously (both sites in parallel)
  - Any decisive result (tempDisabled, permDisabled, success) → email is DONE, skip P2 & P3 entirely
  - "incorrect password" on all 4 attempts on both sites → email survives to Phase 2
- **Phase 2**: Only surviving emails get Password 2 tested
  - Same early-stop rules apply — any decisive result eliminates the email
  - Remaining survivors advance to Phase 3
- **Phase 3**: Only remaining emails get Password 3 tested
  - After Phase 3, any email with ONLY "incorrect password" across ALL passwords → classify as "No Account" (100% guarantee)

**Why This Is Optimal:**

- If P1 resolves 70% of emails on attempt 1-2, those emails NEVER consume P2 or P3 interactions
- Example: 10 emails × 3 passwords — worst case flat approach = 240 interactions; phased = as low as ~80 (67% reduction)
- Early-stop rule compounds: a temp-disabled on attempt 1 of Phase 1 saves up to 22 interactions for that email

**Implementation:**

- [x] `LoginCredential` model supports `passwords: [String]` (ordered list) with backward-compatible Codable
- [x] `PasswordPhasedScheduler` service groups credentials by email, tracks resolved vs surviving per phase
- [x] `ConcurrentAutomationEngine` refactored to execute in password phases instead of flat waves
- [x] `CredentialManagerView` bulk import groups same-email entries into multi-password credentials
- [x] `DualRunView` shows current password phase, surviving email count, and efficiency gain metrics
- [x] `ConcurrentSession` tracks which password phase it belongs to (P1/P2/P3 label)

**Key Rules Preserved:**

- Early-Stop Rule: disabled message on either site → halt BOTH sites for that email immediately
- Current-Run Burn Rule: permDisabled or success → burn current IP/viewport/fingerprint combo
- 4 registered attempts per site required before advancing (full button-color-cycle confirmation)
- "No Account" classification ONLY after ALL passwords exhausted with only "incorrect password" responses
- tempDisabled = 100% account exists (positive signal) regardless of which password phase triggered it
