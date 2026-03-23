# Smart Credential Insights + Revamped Dual Find (Minimum Clicks)

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

## Part 2: Revamped Dual Find — Maximum Efficiency, Minimum Clicks

The current Dual Find requires ~6 interactions (pick site → pick family → pick selector → search → repeat for each family → repeat for other site). The new version reduces this to **1 tap**.

**Features:**

- **One-Tap "Full Probe"** button — probes ALL selector families (username, password, submit) on BOTH sites (Joe + Ignition) in a single action
- Runs 6 checks in parallel (3 families × 2 sites) and returns a consolidated health matrix
- Results displayed as a **site × selector grid** — 2 rows (Joe, Ignition) × 3 columns (Username, Password, Submit)
- Each cell shows: ✅ found + visible, ⚠️ found but hidden, ❌ not found — with match count
- Tapping any cell expands to show the detailed match info (attributes, text preview) — same data as before but in-line
- Proof screenshots captured per-site (not per-selector) to minimize page loads — 2 screenshots total
- Still keeps the manual single-selector probe mode as a secondary option via "Advanced" disclosure
- Auto-uses the URLs and selectors already configured in Settings — zero configuration needed for the standard probe
- Last probe results persist and display on re-entry so you don't lose context
- Probe timestamp shown with relative time ("2 min ago")

**Design:**

- Clean top section with "Full Probe" hero button (large, neon cyan, full width)
- Below it: 2×3 health matrix grid with site labels on left, selector family labels on top
- Each grid cell is a rounded tile with the status icon and match count
- Color coding: green = all good, orange = found but hidden, red = missing, gray = not yet probed
- Expandable detail rows slide down when tapping a cell
- "Advanced" section collapsed by default at bottom for manual single-selector probing (the current Dual Find UI, simplified)
- Connection status badge in the top-right corner
- Proof screenshots shown in a horizontal scroll below the matrix (one per site)

