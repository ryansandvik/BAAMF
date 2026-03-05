import { firestore } from "firebase-functions/v2";
import * as admin from "firebase-admin";

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
function formatMonthId(monthId: string): string {
  const parts = monthId.split("-");
  const year = parts[0];
  const monthNum = parseInt(parts[1], 10);
  const name = MONTH_NAMES[monthNum] ?? monthId;
  return `${name} ${year}`;
}

interface NotificationContent {
  title: string;
  body: string;
}

/**
 * Maps a status string to the notificationPrefs key that gates it.
 * Returns null for statuses that have no notification.
 */
type PrefKey = "nominations" | "reading" | "scoring";

function prefKeyForStatus(status: string): PrefKey | null {
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
function notificationForTransition(
  prevStatus: string | undefined,
  newStatus: string,
  monthLabel: string,
  selectedBookTitle?: string
): NotificationContent | null {
  if (prevStatus === newStatus) return null;

  switch (newStatus) {
    case "submissions":
      return {
        title: "📚 Nominations Open",
        body: `Submit your book picks for ${monthLabel}.`,
      };
    case "vetoes":
      return {
        title: "🚫 Veto Window Open",
        body: `The veto window is now open for ${monthLabel}.`,
      };
    case "voting_r1":
      return {
        title: "🗳️ Round 1 Voting",
        body: `Cast your Round 1 votes for ${monthLabel}!`,
      };
    case "voting_r2":
      return {
        title: "🗳️ Final Voting",
        body: `Final voting is open for ${monthLabel}!`,
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

/**
 * Fetches FCM tokens for all users that have a valid token AND have
 * the given notification preference enabled (defaults to true when unset).
 */
async function getTokensForPref(prefKey: PrefKey | "swaps"): Promise<string[]> {
  const snapshot = await db.collection("users").get();
  const tokens: string[] = [];
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const token = data.fcmToken;
    if (typeof token !== "string" || token.length === 0) continue;
    // Preference defaults to true when not set
    const prefs = (data.notificationPrefs ?? {}) as Record<string, boolean>;
    if (prefs[prefKey] !== false) {
      tokens.push(token);
    }
  }
  return tokens;
}

/** Sends an FCM notification to the provided tokens (batched to ≤500 per call). */
async function sendToTokens(
  tokens: string[],
  title: string,
  body: string
): Promise<void> {
  if (tokens.length === 0) return;

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
// Function: Phase change notifications
// ─────────────────────────────────────────────────────────────────────────────

export const onMonthStatusChange = firestore.onDocumentWritten(
  "months/{monthId}",
  async (event) => {
    const monthId = event.params.monthId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // Document was deleted — nothing to do
    if (!after) return;

    // Historical back-fills should never trigger notifications
    if (after.isHistorical === true) return;

    const prevStatus = before?.status as string | undefined;
    const newStatus = after.status as string;

    // No status change — skip
    if (prevStatus === newStatus) return;

    const prefKey = prefKeyForStatus(newStatus);
    if (!prefKey) return; // No notification defined for this status

    const monthLabel = formatMonthId(monthId);
    const selectedBookTitle = after.selectedBookTitle as string | undefined;

    const content = notificationForTransition(
      prevStatus,
      newStatus,
      monthLabel,
      selectedBookTitle
    );
    if (!content) return;

    // Only send to users who have this notification type enabled
    const tokens = await getTokensForPref(prefKey);
    await sendToTokens(tokens, content.title, content.body);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Function: Swap request notifications
// ─────────────────────────────────────────────────────────────────────────────

export const onSwapRequest = firestore.onDocumentCreated(
  "hostSchedule/{year}/swapRequests/{requestId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const targetId = data.targetId as string | undefined;
    const requesterId = data.requesterId as string | undefined;

    if (!targetId || !requesterId) return;

    // Fetch target token and requester name in parallel
    const [targetSnap, requesterSnap] = await Promise.all([
      db.collection("users").doc(targetId).get(),
      db.collection("users").doc(requesterId).get(),
    ]);

    const targetData = targetSnap.data();
    const targetToken = targetData?.fcmToken as string | undefined;
    if (!targetToken) return;

    // Respect the target user's swap notification preference (defaults true)
    const targetPrefs = (targetData?.notificationPrefs ?? {}) as Record<string, boolean>;
    if (targetPrefs["swaps"] === false) return;

    const requesterName =
      (requesterSnap.data()?.name as string | undefined) ?? "A member";

    await sendToTokens(
      [targetToken],
      "📅 Hosting Swap Request",
      `${requesterName} wants to swap a hosting month with you.`
    );
  }
);
