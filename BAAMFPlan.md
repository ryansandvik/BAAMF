# BAAMF — Product Plan

## Version 1.0 ✅ Complete

### Core Authentication
- [x] Firebase Auth sign-in / sign-up
- [x] Password reset
- [x] Invite code gating (one-time use, 24h expiry)
- [x] Admin role (stored in Firestore, checked via custom claims pattern)

### Member Management
- [x] User profiles stored in `users/{uid}`
- [x] `isAdmin` flag managed in backend

### Club Month Lifecycle
- [x] `clubMonths/{monthId}` document with full status machine:
  - `nominations` → `veto` → `votingR1` → `votingR2` → `reading` → `scoring` → `complete`
  - `hostSelect4` shortcut mode
- [x] Admin: create and manage monthly schedule (`ScheduleView`)
- [x] Admin: advance phase manually (`MonthManagementView`)
- [x] Host setup flow: choose submission type, configure book pick

### Book Nominations & Voting
- [x] Members submit book nominations (Google Books search integration)
- [x] Members edit / delete own submissions during nominations phase
- [x] Veto round: host vetos one book
- [x] Voting Round 1 & Round 2: ranked-choice style selection
- [x] Host-select-4 mode: host picks book directly

### Scoring
- [x] Members score selected book (0.5–10 in 0.5 increments)
- [x] Group average calculated and stored on month doc

### History
- [x] History list: all complete months sorted by date
- [x] History detail: cover, scores, group avg, historical badge
- [x] Admin: edit scores on any completed month (`EditCompletedMonthView`)
- [x] Historical badge on historical entries

### Admin: Historical Book Entry
- [x] Back-fill past club months (`LogHistoricalBookView`)
- [x] Per-member score entry with participation toggle
- [x] `isHistorical: Bool` flag on `ClubMonth`
- [x] Historical entries skipped by push notification Cloud Function

### Profile
- [x] My Favourites section (top-scored books by year, with year selector)
- [x] Notification preferences (per-phase toggles, persisted to Firestore)
- [x] Sign out

### Push Notifications (Firebase Cloud Functions v2)
- [x] Phase transition notifications (nominations, reading, scoring, swap requests)
- [x] Per-user preference filtering (nominations, reading, scoring, swaps)
- [x] Hosting swap request notifications

### Deployment
- [x] TestFlight (internal + external via Beta App Review)
- [x] `aps-environment: production` in entitlements
- [x] `ITSAppUsesNonExemptEncryption = false` in Info.plist
- [x] Firestore security rules for all collections
- [x] Cloud Functions deployed

---

## Version 1.1 — Planned

### Phase A — Role & Identity (foundational, do first)

**Virtual Member Role**
- New `isVirtual: Bool` flag on `users/{uid}` (alongside `isAdmin`), set in backend
- Virtual members participate in nominations, voting, and scoring normally
- Excluded from automatic scheduling algorithm (scheduler skips virtual members when assigning host rotation)
- Admin can still manually assign a virtual member as host for a given month
- No UI badge needed — purely a scheduling constraint

**Profile Picture**
- Firebase Storage: `profilePictures/{uid}.jpg`
- Upload from `ProfileView` using `PhotosUI` (`PhotosPicker`)
- `CoverImage`-style async loader for member avatars throughout the app
- Store download URL at `users/{uid}.photoURL`
- Show avatar in: Profile tab header, member lists (schedule, swap requests, attendance)
- Firestore security rules: users can write only their own `profilePictures/{uid}` path

*Rationale: Group A together because virtual member is a data-model change with no UI footprint, and profile pictures are a natural companion. Both are low-risk, additive changes with no workflow side effects.*

---

### Phase B — Transparency & Attendance (workflow-adjacent, do second)

**Submitter Reveal**
- `submittedBy: String (uid)` is already written on book nomination documents
- Fully anonymous until `reading` phase — no exceptions, including admins and host
- Firestore rule: mask `submittedBy` field on `books/{bookId}` reads until parent month `status` is `reading` or `complete`
- Once revealed: show submitter name (and avatar if profile pictures are shipped) in `HistoryDetailView` and the current month book card on HomeView

**Attendance RSVP**
- New subcollection `months/{monthId}/attendance/{uid}` with `{ attending: Bool, updatedAt: Timestamp }`
- Visible for all months — both active and historical
- HomeView month card: inline "Attending?" toggle for the current user
- Month detail / HistoryDetailView: full attendance list (attending, not attending, no response)
- Attendance is informational only — no effect on phase transitions or scoring
- Firestore rule: users can write only their own attendance doc; all members can read

*Rationale: Group B together — both are display-layer changes on top of existing data. Neither touches the phase state machine.*

---

### Phase C — Automated Deadlines & Smart Notifications (most complex, do last)

**Phase Deadlines**
- New optional fields on `ClubMonth`: `submissionDeadline`, `vetoDeadline`, `votingR1Deadline`, `votingR2Deadline` (all `Timestamp?`)
- App-wide default settings stored in Firestore (e.g. `settings/defaults`): submissions = 7 days, veto = 2 days, VR1 = 2 days, VR2 = 2 days — admins configure from a Settings section in the admin area
- When advancing a phase, host can override the default deadline for that specific phase
- Deadlines not applicable in `hostSelect4` mode
- Cloud Scheduler: runs every 15 min, queries months where any deadline has passed and status matches, auto-advances the phase
- Manual override always available — host/admin can advance early from `MonthManagementView`

**Deadline-Aware Notifications**
- Phase transition notifications extended to include deadline when set (e.g. "Nominations are open — submit by March 12")
- Reminder sent 1 hour before each deadline to members who haven't yet participated in that phase (same logic as existing participation reminders)
- At the same 1-hour mark, host receives a separate notification: "Submissions close in 1 hour — the phase will advance automatically"
- Host also notified when auto-advance actually fires

**Data Export (design now, build later)**
- Export format: CSV emailed to requesting admin's registered email via a callable Cloud Function
- Data per row: month, book title, author, host, each member's nomination, R1 votes (per book per member), R2 votes, veto decision, score per member, group average
- ✅ Vote data model already export-ready: votes are stored as `votingR1Voters: [uid]` and `votingR2Voters: [uid]` arrays directly on each book document in `months/{monthId}/books/{bookId}` — no separate vote documents, no missing fields
- Full export is a fan-out read across `months`, `months/{id}/books`, `months/{id}/scores` — all data is already there
- Build trigger: single Cloud Function + admin button when ready

*Rationale: Phase C last — automated deadlines require Cloud Scheduler and careful testing to avoid race conditions (e.g. host manually advancing at the same moment the scheduler fires). Notification changes depend on deadlines existing. Export deferred but data model is confirmed sound.*

---

## Design Decisions Log

| Question | Decision |
|---|---|
| Virtual member UI badge | No badge — scheduling-only constraint |
| Submitter reveal timing | Fully anonymous until `reading` phase, including admins |
| Attendance scope | All months — current and historical |
| Deadline defaults storage | App-wide Firestore settings, admin-configurable; host can override per-phase |
| Auto-advance host notification | Yes — 1h warning + confirmation when auto-advance fires |
| Vote data model | ✅ Votes embedded as `votingR1Voters`/`votingR2Voters` arrays on book docs — export-ready |
