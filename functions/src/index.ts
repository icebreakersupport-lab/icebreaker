import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

initializeApp();

const db = getFirestore();

/**
 * Mutual unlock: create the conversation when both meetup participants
 * submit a "we_got_this" post-meet decision.
 *
 * Trigger path: meetups/{meetupId}/decisions/{uid}
 *
 * Invariants enforced here (server-side, cannot be forged by clients):
 *   1. Both decision documents must exist before a conversation is created.
 *   2. Both decisions must equal 'we_got_this'.
 *   3. The conversation document ID equals the meetupId — deterministic,
 *      so clients can predict it without a list query.
 *   4. Creation is idempotent: if the conversation already exists the
 *      function exits without writing, preventing duplicates even if the
 *      function is retried or both users write their decisions simultaneously.
 *   5. participantNames and participantPhotos are sourced from the meetup
 *      document written by the accepting client — they are never supplied
 *      by the user who submits the decision.
 *
 * Firestore rules set conversations.create = false, so this is the ONLY
 * code path that can create a conversation document.
 */
export const onMeetupDecisionWritten = onDocumentWritten(
  'meetups/{meetupId}/decisions/{uid}',
  async (event) => {
    const { meetupId } = event.params;

    // ── 1. Load the parent meetup document ──────────────────────────────────
    const meetupRef = db.collection('meetups').doc(meetupId);
    const meetupSnap = await meetupRef.get();

    if (!meetupSnap.exists) {
      console.warn(`[unlock] meetup ${meetupId} not found — skipping`);
      return;
    }

    const meetup = meetupSnap.data()!;
    const participants: string[] = meetup.participants ?? [];

    if (participants.length !== 2) {
      console.warn(
        `[unlock] meetup ${meetupId} has ${participants.length} participants — expected 2`,
      );
      return;
    }

    const [uid1, uid2] = participants;

    // ── 2. Load both decision documents ─────────────────────────────────────
    const decisionsRef = db.collection('meetups').doc(meetupId).collection('decisions');
    const [dec1Snap, dec2Snap] = await Promise.all([
      decisionsRef.doc(uid1).get(),
      decisionsRef.doc(uid2).get(),
    ]);

    if (!dec1Snap.exists || !dec2Snap.exists) {
      // Only one user has decided — wait for the other.
      console.log(`[unlock] ${meetupId}: waiting for both decisions`);
      return;
    }

    const dec1 = dec1Snap.data()!;
    const dec2 = dec2Snap.data()!;

    // ── 3. Check mutual agreement ────────────────────────────────────────────
    if (dec1.decision !== 'we_got_this' || dec2.decision !== 'we_got_this') {
      console.log(
        `[unlock] ${meetupId}: no mutual match ` +
          `(${uid1}=${dec1.decision}, ${uid2}=${dec2.decision})`,
      );
      // Signal the meetup as concluded without a match so listening clients
      // can update their waiting UI immediately.
      await meetupRef
        .update({ status: 'no_match', concludedAt: FieldValue.serverTimestamp() })
        .catch((err) => console.error('[unlock] status update failed:', err));
      return;
    }

    // ── 4. Idempotency check ─────────────────────────────────────────────────
    // Conversation ID = meetupId.  Deterministic — clients can poll for it
    // without a list query.
    const convRef = db.collection('conversations').doc(meetupId);
    const convSnap = await convRef.get();

    if (convSnap.exists) {
      console.log(`[unlock] conversation ${meetupId} already exists — no-op`);
      return;
    }

    // ── 5. Create the conversation ───────────────────────────────────────────
    // Participant metadata is sourced from the meetup doc, not from the
    // decision payload, so clients cannot inject arbitrary names or photos.
    const names: Record<string, string> = meetup.participantNames ?? {};
    const photos: Record<string, string> = meetup.participantPhotos ?? {};

    await convRef.set({
      participants: [uid1, uid2],
      participantNames: names,
      participantPhotos: photos,
      status: 'active',
      lastMessage: '',
      lastMessageAt: FieldValue.serverTimestamp(),
      [`unreadCount_${uid1}`]: 0,
      [`unreadCount_${uid2}`]: 0,
      createdAt: FieldValue.serverTimestamp(),
      sourceIcebreakerId: meetup.icebreakerId ?? '',
      meetupId: meetupId,
    });

    // Mark the meetup as matched.
    await meetupRef
      .update({ status: 'matched', matchedAt: FieldValue.serverTimestamp() })
      .catch((err) => console.error('[unlock] meetup status update failed:', err));

    console.log(`[unlock] conversation created for meetup ${meetupId}`);
  },
);

/**
 * Block enforcement: archive any shared conversation when a user blocks another.
 *
 * Trigger: creation of users/{uid}/blockedUsers/{blockedUid}
 *
 * The function queries for conversations where uid is a participant, then
 * filters for any that also contain blockedUid.  Each match is set to
 * status='blocked', which:
 *   - Prevents new messages via the Firestore security rule (status != 'active').
 *   - Makes _verifyConversationAccess() in the chat thread return false,
 *     hiding the composer and stream without a client-side block list check.
 *
 * The function is idempotent: re-running it on an already-blocked conversation
 * is a no-op (update is a merge, timestamp will refresh but status stays blocked).
 */
export const onUserBlocked = onDocumentCreated(
  'users/{uid}/blockedUsers/{blockedUid}',
  async (event) => {
    const { uid, blockedUid } = event.params;

    // Find all conversations where the blocker is a participant.
    const convSnap = await db
      .collection('conversations')
      .where('participants', 'array-contains', uid)
      .get();

    // Filter to conversations that also include the blocked user.
    const sharedConvs = convSnap.docs.filter((doc) => {
      const participants: string[] = doc.data().participants ?? [];
      return participants.includes(blockedUid);
    });

    if (sharedConvs.length === 0) {
      console.log(`[block] no shared conversation between ${uid} and ${blockedUid}`);
      return;
    }

    await Promise.all(
      sharedConvs.map((doc) =>
        doc.ref
          .update({
            status: 'blocked',
            blockedAt: FieldValue.serverTimestamp(),
            blockedBy: uid,
          })
          .catch((err) =>
            console.error(`[block] failed to archive conversation ${doc.id}:`, err),
          ),
      ),
    );

    console.log(
      `[block] archived ${sharedConvs.length} conversation(s) ` +
        `between ${uid} and ${blockedUid}`,
    );
  },
);

/**
 * Chat message notification with Do Not Disturb enforcement.
 *
 * Trigger: every new message document in conversations/{conversationId}/messages/{messageId}
 *
 * Suppression rules (DND gate):
 *   • If recipient.isLive == false AND recipient.doNotDisturb == true → skip.
 *   • isLive is written by the Flutter client in LiveSession.goLive() /
 *     endSession().  It is reset to false on cold-start crash recovery
 *     (hydrateCredits) so a force-killed session never leaves DND permanently
 *     active.
 *
 * No FCM token → skip silently (token written by client on app init; TODO).
 * Stale/invalid token → delete token from user doc so future sends are skipped
 * until the client registers a fresh one.
 *
 * Notification types affected: ONLY 'chat_message'.
 * Icebreaker received / match confirmed / session alerts are NOT affected.
 */
/**
 * Report escalation: promote a reported user to 'under_review' once 3 unique
 * reporters have filed against them.
 *
 * Trigger: creation of users/{reportedId}/reportedBy/{reporterId}
 *
 * Using the admin SDK here means:
 *   - No Firestore rule allows a normal client to set status = 'under_review'.
 *   - The count is authoritative (server-side aggregation, not client-supplied).
 *   - The status transition is one-way: active → under_review only.
 *     Reversing to 'active' or escalating to 'suspended' is a separate admin op.
 *
 * Idempotency: if status is already 'under_review' or 'suspended' the function
 * exits without writing, so retries are safe.
 */
export const onReportedByCreated = onDocumentCreated(
  'users/{reportedId}/reportedBy/{reporterId}',
  async (event) => {
    const { reportedId } = event.params;

    const userRef = db.collection('users').doc(reportedId);

    // Count all unique reporters (admin SDK bypasses security rules).
    const countSnap = await userRef.collection('reportedBy').count().get();
    const uniqueReporters = countSnap.data().count;

    if (uniqueReporters < 3) {
      console.log(`[report] ${reportedId} has ${uniqueReporters} reporter(s) — threshold not met`);
      return;
    }

    // Only escalate if the user is still 'active' (or has no status set).
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      console.warn(`[report] user ${reportedId} not found — skipping escalation`);
      return;
    }

    const currentStatus = (userSnap.data()?.status as string) ?? 'active';
    if (currentStatus !== 'active') {
      console.log(`[report] ${reportedId} already has status='${currentStatus}' — no change`);
      return;
    }

    await userRef.update({ status: 'under_review' });
    console.log(
      `[report] ${reportedId} promoted to under_review ` +
      `(${uniqueReporters} unique reporters)`,
    );
  },
);

export const onNewChatMessage = onDocumentCreated(
  'conversations/{conversationId}/messages/{messageId}',
  async (event) => {
    const { conversationId } = event.params;
    const msgData = event.data?.data();
    if (!msgData) return;

    const senderId: string = msgData.senderId;
    const text: string = msgData.text ?? '';
    if (!senderId) return;

    // ── 1. Load the parent conversation ───────────────────────────────────────
    const convRef = db.collection('conversations').doc(conversationId);
    const convSnap = await convRef.get();
    if (!convSnap.exists) {
      console.warn(`[chat-notif] conversation ${conversationId} not found`);
      return;
    }

    const conv = convSnap.data()!;
    const participants: string[] = conv.participants ?? [];

    // ── 2. Determine recipient ─────────────────────────────────────────────────
    const recipientId = participants.find((p) => p !== senderId);
    if (!recipientId) {
      console.warn(`[chat-notif] no recipient found in ${conversationId}`);
      return;
    }

    // ── 3. Load recipient user doc ─────────────────────────────────────────────
    const recipientRef = db.collection('users').doc(recipientId);
    const recipientSnap = await recipientRef.get();
    if (!recipientSnap.exists) {
      console.warn(`[chat-notif] recipient ${recipientId} not found`);
      return;
    }

    const recipient = recipientSnap.data()!;
    const isLive: boolean = (recipient.isLive as boolean) ?? false;
    const doNotDisturb: boolean = (recipient.doNotDisturb as boolean) ?? false;
    const notifMessages: boolean = (recipient.notifMessages as boolean) ?? true;
    const fcmToken: string | undefined = recipient.fcmToken as string | undefined;

    // ── 4. Preference gates ────────────────────────────────────────────────────

    // Gate 4a — notifMessages: hard opt-out from all chat push notifications.
    // This is an absolute suppress regardless of live state or DND.
    if (!notifMessages) {
      console.log(`[chat-notif] suppressed for ${recipientId}: notifMessages=false`);
      return;
    }

    // Gate 4b — DND: conditional suppress while user is not live.
    // Being live overrides DND (user is present and expects notifications).
    if (!isLive && doNotDisturb) {
      console.log(
        `[chat-notif] suppressed for ${recipientId}: ` +
        `isLive=${isLive} doNotDisturb=${doNotDisturb}`,
      );
      return;
    }

    // ── 5. FCM token guard ─────────────────────────────────────────────────────
    if (!fcmToken) {
      // Normal until the client has registered a token.
      console.log(`[chat-notif] no FCM token for ${recipientId} — skipping`);
      return;
    }

    // ── 6. Send ────────────────────────────────────────────────────────────────
    const participantNames = (conv.participantNames as Record<string, string>) ?? {};
    const senderName = participantNames[senderId] ?? 'Someone';
    const body = text.length > 100 ? `${text.substring(0, 100)}\u2026` : text;

    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: senderName,
          body: body || 'New message',
        },
        data: {
          type: 'chat_message',
          conversationId,
          senderId,
        },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
        },
        android: {
          notification: { sound: 'default', channelId: 'chat_messages' },
        },
      });
      console.log(`[chat-notif] sent to ${recipientId} in ${conversationId}`);
    } catch (err: unknown) {
      // Stale token: remove it so future sends don't retry a dead token.
      const code = (err as { code?: string }).code;
      if (code === 'messaging/registration-token-not-registered') {
        console.log(`[chat-notif] stale token for ${recipientId} — clearing`);
        await recipientRef
          .update({ fcmToken: FieldValue.delete() })
          .catch((e) => console.error('[chat-notif] token clear failed:', e));
      } else {
        console.error('[chat-notif] FCM send failed:', err);
      }
    }
  },
);
