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
    case "complete":
      return {
        title: "✅ Month Complete",
        body: `${monthLabel} is wrapped up!`,
      };
    default:
      return null;
  }
}

/** Fetches FCM tokens for all users that have one. */
async function getAllFCMTokens(): Promise<string[]> {
  const snapshot = await db.collection("users").get();
  const tokens: string[] = [];
  for (const doc of snapshot.docs) {
    const token = doc.data().fcmToken;
    if (typeof token === "string" && token.length > 0) {
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

  // FCM sendEachForMulticast supports up to 500 tokens per request
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
// Triggers on any write to months/{monthId} and sends a push notification
// to all members when the status field advances to a new phase.
// ─────────────────────────────────────────────────────────────────────────────

export const onMonthStatusChange = firestore.onDocumentWritten(
  "months/{monthId}",
  async (event) => {
    const monthId = event.params.monthId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // Document was deleted — nothing to do
    if (!after) return;

    const prevStatus = before?.status as string | undefined;
    const newStatus = after.status as string;

    // No status change — skip
    if (prevStatus === newStatus) return;

    const monthLabel = formatMonthId(monthId);
    const selectedBookTitle = after.selectedBookTitle as string | undefined;

    const content = notificationForTransition(
      prevStatus,
      newStatus,
      monthLabel,
      selectedBookTitle
    );
    if (!content) return;

    const tokens = await getAllFCMTokens();
    await sendToTokens(tokens, content.title, content.body);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Function: Swap request notifications
// Triggers when a new swap request document is created and notifies the
// member who is being asked to swap.
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

    const targetToken = targetSnap.data()?.fcmToken as string | undefined;
    if (!targetToken) return;

    const requesterName =
      (requesterSnap.data()?.name as string | undefined) ?? "A member";

    await sendToTokens(
      [targetToken],
      "📅 Hosting Swap Request",
      `${requesterName} wants to swap a hosting month with you.`
    );
  }
);
