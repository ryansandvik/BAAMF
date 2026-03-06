"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onBookReadItVetoed = exports.processDeadlines = exports.onSwapRequest = exports.onMonthStatusChange = void 0;
const v2_1 = require("firebase-functions/v2");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
const MONTH_NAMES = [
    "", // index 0 unused
    "January", "February", "March", "April",
    "May", "June", "July", "August",
    "September", "October", "November", "December",
];
/** Converts a Firestore month ID ("2026-03") to a human label ("March 2026"). */
function formatMonthId(monthId) {
    var _a;
    const parts = monthId.split("-");
    const year = parts[0];
    const monthNum = parseInt(parts[1], 10);
    const name = (_a = MONTH_NAMES[monthNum]) !== null && _a !== void 0 ? _a : monthId;
    return `${name} ${year}`;
}
/** Formats a Firestore Timestamp to a short date string, e.g. "March 12". */
function formatDeadline(ts) {
    var _a;
    const d = ts.toDate();
    const month = (_a = MONTH_NAMES[d.getMonth() + 1]) !== null && _a !== void 0 ? _a : "";
    return `${month} ${d.getDate()}`;
}
function prefKeyForStatus(status) {
    switch (status) {
        case "submissions":
        case "vetoes":
        case "voting_r1":
        case "voting_r2":
            return "nominations";
        case "reading":
            return "reading";
        case "scoring":
            return "scoring";
        default:
            return null;
    }
}
/** Returns the notification to send for a given status transition, or null if none. */
function notificationForTransition(prevStatus, newStatus, monthLabel, selectedBookTitle, deadline) {
    if (prevStatus === newStatus)
        return null;
    const deadlineStr = deadline ? ` — closes ${formatDeadline(deadline)}` : "";
    switch (newStatus) {
        case "submissions":
            return {
                title: "📚 Nominations Open",
                body: `Submit your book picks for ${monthLabel}${deadlineStr}.`,
            };
        case "vetoes":
            return {
                title: "🚫 Veto Window Open",
                body: `The veto window is now open for ${monthLabel}${deadlineStr}.`,
            };
        case "voting_r1":
            return {
                title: "🗳️ Round 1 Voting",
                body: `Cast your Round 1 votes for ${monthLabel}${deadlineStr}!`,
            };
        case "voting_r2":
            return {
                title: "🗳️ Final Voting",
                body: `Final voting is open for ${monthLabel}${deadlineStr}!`,
            };
        case "reading": {
            const bookLabel = selectedBookTitle
                ? `"${selectedBookTitle}"`
                : "The chosen book";
            return {
                title: "📖 Book Chosen!",
                body: `${bookLabel} is the pick for ${monthLabel}!`,
            };
        }
        case "scoring":
            return {
                title: "⭐ Time to Score",
                body: `Rate the book for ${monthLabel}!`,
            };
        default:
            return null;
    }
}
/** The Firestore deadline field name for a given status. */
function deadlineFieldForStatus(status) {
    switch (status) {
        case "submissions": return "submissionDeadline";
        case "vetoes": return "vetoDeadline";
        case "voting_r1": return "votingR1Deadline";
        case "voting_r2": return "votingR2Deadline";
        default: return null;
    }
}
/** The next status after auto-advancing. */
function nextStatusFor(status) {
    switch (status) {
        case "submissions": return "vetoes";
        case "vetoes": return "voting_r1";
        case "voting_r1": return "voting_r2";
        case "voting_r2": return "reading";
        default: return null;
    }
}
/**
 * Fetches FCM tokens for all users that have a valid token AND have
 * the given notification preference enabled (defaults to true when unset).
 */
async function getTokensForPref(prefKey) {
    var _a;
    const snapshot = await db.collection("users").get();
    const tokens = [];
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const token = data.fcmToken;
        if (typeof token !== "string" || token.length === 0)
            continue;
        // Preference defaults to true when not set
        const prefs = ((_a = data.notificationPrefs) !== null && _a !== void 0 ? _a : {});
        if (prefs[prefKey] !== false) {
            tokens.push(token);
        }
    }
    return tokens;
}
/** Fetches the FCM token for a single user, respecting their preference. */
async function getTokenForUser(uid, prefKey) {
    var _a;
    const snap = await db.collection("users").doc(uid).get();
    const data = snap.data();
    if (!data)
        return null;
    const token = data.fcmToken;
    if (!token)
        return null;
    const prefs = ((_a = data.notificationPrefs) !== null && _a !== void 0 ? _a : {});
    if (prefs[prefKey] === false)
        return null;
    return token;
}
/** Sends an FCM notification to the provided tokens (batched to ≤500 per call). */
async function sendToTokens(tokens, title, body) {
    if (tokens.length === 0)
        return;
    for (let i = 0; i < tokens.length; i += 500) {
        const chunk = tokens.slice(i, i + 500);
        await messaging.sendEachForMulticast({
            tokens: chunk,
            notification: { title, body },
            apns: {
                payload: { aps: { sound: "default" } },
            },
        });
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// Auto-advance helpers (mirror the iOS client logic in TypeScript)
// ─────────────────────────────────────────────────────────────────────────────
const R2_ADVANCE_COUNT = 3; // must match K.Voting.r2AdvanceCount in iOS
async function autoAdvanceVotingR1toR2(monthId, monthRef) {
    const booksSnap = await db
        .collection(`months/${monthId}/books`)
        .get();
    const scores = booksSnap.docs
        .filter((d) => !(d.data().isRemovedByVeto === true))
        .map((d) => {
        var _a;
        const data = d.data();
        const raw = ((_a = data.votingR1Voters) !== null && _a !== void 0 ? _a : []).length;
        const penalty = data.vetoType2Penalty === true ? -1 : 0; // deduct 1 vote as penalty
        return { ref: d.ref, netVotes: raw + penalty };
    })
        .sort((a, b) => b.netVotes - a.netVotes);
    const cutoff = scores.length >= R2_ADVANCE_COUNT
        ? scores[R2_ADVANCE_COUNT - 1].netVotes
        : scores.length > 0
            ? scores[scores.length - 1].netVotes
            : 0;
    const batch = db.batch();
    batch.update(monthRef, { status: "voting_r2" });
    for (const entry of scores) {
        if (entry.netVotes >= cutoff) {
            batch.update(entry.ref, { advancedToR2: true });
        }
    }
    await batch.commit();
}
async function autoAdvanceVotingR2toReading(monthId, monthRef) {
    var _a, _b;
    const booksSnap = await db
        .collection(`months/${monthId}/books`)
        .where("advancedToR2", "==", true)
        .get();
    const candidates = booksSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            data: d.data(),
            r2Count: ((_a = d.data().votingR2Voters) !== null && _a !== void 0 ? _a : []).length,
        });
    });
    candidates.sort((a, b) => b.r2Count - a.r2Count);
    const winner = candidates[0];
    const update = {
        status: "reading",
    };
    if (winner) {
        update["selectedBookId"] = winner.id;
        update["selectedBookTitle"] = (_a = winner.data.title) !== null && _a !== void 0 ? _a : "";
        update["selectedBookAuthor"] = (_b = winner.data.author) !== null && _b !== void 0 ? _b : "";
        if (winner.data.coverUrl)
            update["selectedBookCoverUrl"] = winner.data.coverUrl;
        if (winner.data.submitterId)
            update["selectedBookSubmitterId"] = winner.data.submitterId;
    }
    await monthRef.update(update);
}
async function simpleStatusAdvance(monthRef, newStatus) {
    await monthRef.update({ status: newStatus });
}
// ─────────────────────────────────────────────────────────────────────────────
// Function: Phase change notifications (on status write)
// ─────────────────────────────────────────────────────────────────────────────
exports.onMonthStatusChange = v2_1.firestore.onDocumentWritten("months/{monthId}", async (event) => {
    var _a, _b, _c, _d;
    const monthId = event.params.monthId;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    // Document was deleted — nothing to do
    if (!after)
        return;
    // Historical back-fills should never trigger notifications
    if (after.isHistorical === true)
        return;
    const prevStatus = before === null || before === void 0 ? void 0 : before.status;
    const newStatus = after.status;
    // No status change — skip
    if (prevStatus === newStatus)
        return;
    const prefKey = prefKeyForStatus(newStatus);
    if (!prefKey)
        return; // No notification defined for this status
    const monthLabel = formatMonthId(monthId);
    const selectedBookTitle = after.selectedBookTitle;
    // Include the deadline in the notification body if present
    const deadlineField = deadlineFieldForStatus(newStatus);
    const deadline = deadlineField
        ? after[deadlineField]
        : undefined;
    const content = notificationForTransition(prevStatus, newStatus, monthLabel, selectedBookTitle, deadline);
    if (!content)
        return;
    // Only send to users who have this notification type enabled
    const tokens = await getTokensForPref(prefKey);
    await sendToTokens(tokens, content.title, content.body);
});
// ─────────────────────────────────────────────────────────────────────────────
// Function: Swap request notifications
// ─────────────────────────────────────────────────────────────────────────────
exports.onSwapRequest = v2_1.firestore.onDocumentCreated("hostSchedule/{year}/swapRequests/{requestId}", async (event) => {
    var _a, _b, _c, _d;
    const data = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!data)
        return;
    const targetId = data.targetId;
    const requesterId = data.requesterId;
    if (!targetId || !requesterId)
        return;
    // Fetch target token and requester name in parallel
    const [targetSnap, requesterSnap] = await Promise.all([
        db.collection("users").doc(targetId).get(),
        db.collection("users").doc(requesterId).get(),
    ]);
    const targetData = targetSnap.data();
    const targetToken = targetData === null || targetData === void 0 ? void 0 : targetData.fcmToken;
    if (!targetToken)
        return;
    // Respect the target user's swap notification preference (defaults true)
    const targetPrefs = ((_b = targetData === null || targetData === void 0 ? void 0 : targetData.notificationPrefs) !== null && _b !== void 0 ? _b : {});
    if (targetPrefs["swaps"] === false)
        return;
    const requesterName = (_d = (_c = requesterSnap.data()) === null || _c === void 0 ? void 0 : _c.name) !== null && _d !== void 0 ? _d : "A member";
    await sendToTokens([targetToken], "📅 Hosting Swap Request", `${requesterName} wants to swap a hosting month with you.`);
});
// ─────────────────────────────────────────────────────────────────────────────
// Scheduled: Auto-advance phases + 1-hour reminders (every 15 minutes)
// ─────────────────────────────────────────────────────────────────────────────
exports.processDeadlines = v2_1.scheduler.onSchedule({ schedule: "every 15 minutes", timeoutSeconds: 540 }, async () => {
    var _a;
    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();
    // The statuses that have deadlines
    const deadlineStatuses = ["submissions", "vetoes", "voting_r1", "voting_r2"];
    const snap = await db
        .collection("months")
        .where("status", "in", deadlineStatuses)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data();
        const monthId = doc.id;
        const monthRef = doc.ref;
        const status = data.status;
        if (data.isHistorical === true)
            continue;
        const deadlineField = deadlineFieldForStatus(status);
        if (!deadlineField)
            continue;
        const deadline = data[deadlineField];
        if (!deadline)
            continue;
        const deadlineMs = deadline.toMillis();
        // ── 1-hour reminder ──────────────────────────────────────────────────
        // Send if deadline is 45–90 minutes away and reminder hasn't been sent yet.
        const reminderKey = `deadlineReminderSent.${deadlineField}`;
        const reminderAlreadySent = ((_a = data.deadlineReminderSent) !== null && _a !== void 0 ? _a : {})[deadlineField] === true;
        const minutesUntilDeadline = (deadlineMs - nowMs) / 60000;
        if (!reminderAlreadySent && minutesUntilDeadline >= 45 && minutesUntilDeadline <= 90) {
            const monthLabel = formatMonthId(monthId);
            const hostId = data.hostId;
            // Notify all members
            const memberTokens = await getTokensForPref("nominations");
            await sendToTokens(memberTokens, "⏰ Deadline in 1 Hour", `${phaseDisplayName(status)} closes in about an hour for ${monthLabel}.`);
            // Notify host separately (they get a different message)
            if (hostId) {
                const hostToken = await getTokenForUser(hostId, "nominations");
                if (hostToken && !memberTokens.includes(hostToken)) {
                    await sendToTokens([hostToken], "⏰ Phase Closing Soon", `${phaseDisplayName(status)} for ${monthLabel} closes in ~1 hour — it will auto-advance at the deadline.`);
                }
            }
            // Mark reminder as sent
            await monthRef.update({ [reminderKey]: true });
        }
        // ── Auto-advance ─────────────────────────────────────────────────────
        if (deadlineMs > nowMs)
            continue; // deadline hasn't passed yet
        const newStatus = nextStatusFor(status);
        if (!newStatus)
            continue;
        try {
            switch (status) {
                case "voting_r1":
                    await autoAdvanceVotingR1toR2(monthId, monthRef);
                    break;
                case "voting_r2":
                    await autoAdvanceVotingR2toReading(monthId, monthRef);
                    break;
                default:
                    await simpleStatusAdvance(monthRef, newStatus);
            }
            // Notify host that auto-advance fired
            const hostId = data.hostId;
            if (hostId) {
                const monthLabel = formatMonthId(monthId);
                const hostToken = await getTokenForUser(hostId, "nominations");
                if (hostToken) {
                    await sendToTokens([hostToken], "🔄 Phase Auto-Advanced", `${monthLabel} automatically moved to ${phaseDisplayName(newStatus)} because the deadline passed.`);
                }
            }
        }
        catch (err) {
            console.error(`Auto-advance failed for ${monthId}:`, err);
        }
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// Function: Notify book submitter when their book is Read It'd
// ─────────────────────────────────────────────────────────────────────────────
exports.onBookReadItVetoed = v2_1.firestore.onDocumentWritten("months/{monthId}/books/{bookId}", async (event) => {
    var _a, _b, _c, _d, _e;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    // Only act when isRemovedByVeto flips from falsy → true
    if (!after)
        return;
    if (after.isRemovedByVeto !== true)
        return;
    if ((before === null || before === void 0 ? void 0 : before.isRemovedByVeto) === true)
        return; // already removed — no re-notify
    const monthId = event.params.monthId;
    const submitterId = after.submitterId;
    if (!submitterId)
        return;
    // Skip historical months
    const monthSnap = await db.collection("months").doc(monthId).get();
    if (((_e = monthSnap.data()) === null || _e === void 0 ? void 0 : _e.isHistorical) === true)
        return;
    const bookTitle = after.title;
    const monthLabel = formatMonthId(monthId);
    const token = await getTokenForUser(submitterId, "nominations");
    if (!token)
        return;
    const body = bookTitle
        ? `"${bookTitle}" was removed from ${monthLabel}. You can submit a replacement.`
        : `Your submission was removed from ${monthLabel}. You can submit a replacement.`;
    await sendToTokens([token], "📚 Your Book Was Removed", body);
});
// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
function phaseDisplayName(status) {
    switch (status) {
        case "submissions": return "Submissions";
        case "vetoes": return "Veto Window";
        case "voting_r1": return "Round 1 Voting";
        case "voting_r2": return "Final Voting";
        case "reading": return "Reading";
        case "scoring": return "Scoring";
        default: return status;
    }
}
//# sourceMappingURL=index.js.map