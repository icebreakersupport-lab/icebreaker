import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

initializeApp();

const db = getFirestore();

const MEETUP_MATCH_COLOR_HEXES = [
  '#FF073A', // neon red
  '#1F51FF', // neon blue
  '#FF6E00', // neon orange
  '#FFEE00', // neon yellow
  '#BF00FF', // neon purple
  '#39FF14', // neon green
] as const;

function chooseMeetupMatchColorHex(seed: string): string {
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) {
    hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  }
  return MEETUP_MATCH_COLOR_HEXES[hash % MEETUP_MATCH_COLOR_HEXES.length];
}

function pickMeetupRenderPhoto(
  liveSessionData: FirebaseFirestore.DocumentData | undefined,
  profileData: FirebaseFirestore.DocumentData | undefined,
): string {
  const liveSelfieUrl = liveSessionData?.liveSelfieUrl;
  if (typeof liveSelfieUrl === 'string' && liveSelfieUrl.trim().length > 0) {
    return liveSelfieUrl;
  }
  const profilePhotoUrl = profileData?.primaryPhotoUrl;
  return typeof profilePhotoUrl === 'string' ? profilePhotoUrl : '';
}

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

    // ── 6. Write the permanent match record ─────────────────────────────────
    // `matches/{meetupId}` is an immutable snapshot of the moment of matching:
    // participants, names, photos, and the match colour as they were when the
    // ice broke.  Unlike `conversations` (which mutates on every chat message
    // and can flip to status='blocked'), this doc is a permanent ledger of
    // "these two users matched on this date."  Useful for analytics, profile
    // showcases, and any future feature that needs match history regardless
    // of the chat's current state.
    //
    // We reach this block only on the first run-through (the convSnap.exists
    // guard above bails on subsequent fires), so a single set() is safe and
    // idempotent in practice.
    const matchRef = db.collection('matches').doc(meetupId);
    await matchRef.set({
      participants: [uid1, uid2],
      participantNames: names,
      participantPhotos: photos,
      matchColorHex: (meetup.matchColorHex as string | undefined) ?? '',
      matchedAt: FieldValue.serverTimestamp(),
      meetupId: meetupId,
      conversationId: meetupId,
      sourceIcebreakerId: meetup.icebreakerId ?? '',
    });

    // Mark the meetup as matched.
    await meetupRef
      .update({ status: 'matched', matchedAt: FieldValue.serverTimestamp() })
      .catch((err) => console.error('[unlock] meetup status update failed:', err));

    console.log(`[unlock] conversation + match record created for meetup ${meetupId}`);
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

// ── Meetup / Icebreaker state-machine constants ────────────────────────────────

const FIND_TIMER_SECONDS = 300; // 5 min — mirrors AppConstants.findTimerSeconds
const TALK_TIMER_SECONDS = 600; // 10 min — mirrors AppConstants.conversationTimerSeconds
const DECISION_WINDOW_SECONDS = 300; // 5 min grace for both users to submit a post-meet decision
const FREE_ICEBREAKER_CREDITS = 3; // mirrors AppConstants.freeIcebreakerCreditsPerSignup

/**
 * Statuses that release a meetup's participants from the "in-meetup" lock.
 * When a meetup transitions INTO any of these, [onMeetupTerminal] clears
 * users.{uid}.currentMeetupId on both participants so they become eligible
 * for Nearby discovery again.
 *
 *   matched            — both swiped we_got_this; conversation now exists.
 *   ended              — explicit end via endRequests (continued_private exit).
 *   no_match           — at least one swiped nice_meeting_you, OR the
 *                        decision window elapsed without both deciding.
 *   expired_finding    — find-timer elapsed without both confirming.
 *   cancelled_finding  — a participant tapped exit during finding and confirmed.
 *   cancelled_talking  — a participant tapped exit during talking and confirmed.
 */
const TERMINAL_MEETUP_STATUSES: ReadonlySet<string> = new Set([
  'matched',
  'ended',
  'no_match',
  'expired_finding',
  'cancelled_finding',
  'cancelled_talking',
]);

/**
 * respondToIcebreaker — the only legal path for an icebreaker to advance from
 * 'sent' to 'accepted' or 'declined'.
 *
 * Why a callable, not a client-side update:
 *   firestore.rules forbids icebreaker updates entirely (allow update,delete:
 *   if false) precisely because acceptance has credit + meetup-creation side
 *   effects.  A forgeable client write of {status: 'accepted'} would let any
 *   recipient mint a meetup without paying the icebreaker credit.  Routing the
 *   transition through a callable lets the admin SDK do the whole thing
 *   atomically, with the rule layer guaranteeing no other path exists.
 *
 * Atomic transaction (accept):
 *   1. Read icebreakers/{id}; assert recipientId == auth.uid AND status == 'sent'
 *      AND now < expiresAt.
 *   2. Read recipient users/{uid}; apply 24-h credit reset window if expired,
 *      then assert credits > 0.  Throws 'no-credits' otherwise.
 *   3. Read sender + recipient live_sessions/{uid} + profiles/{uid} and
 *      snapshot the meetup-render photo for each participant. Prefer the
 *      active GO LIVE verification selfie; fall back to primary profile
 *      photo if the session selfie is missing.
 *   4. Decrement recipient.icebreakerCredits.
 *   5. Create meetups/{auto-id} with status='finding', foundConfirmedBy=[],
 *      participants=[senderId, recipientId], participantNames/Photos
 *      denormalised, and a shared meetup matchColorHex. findExpiresAt is
 *      stamped by [onMeetupCreated], not here, so the timer starts on the
 *      trigger-fired write rather than the transaction commit.
 *   6. Flip icebreaker to status='accepted' with meetupId.
 *
 * Decline path is the same shape minus the meetup + credit work — just a
 * status flip.
 *
 * Returns { meetupId } on accept so the client knows where to navigate.
 */
export const respondToIcebreaker = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;
  const data = (request.data ?? {}) as { icebreakerId?: unknown; action?: unknown };
  const icebreakerId = data.icebreakerId;
  const action = data.action;

  if (typeof icebreakerId !== 'string' || icebreakerId.length === 0) {
    throw new HttpsError('invalid-argument', 'icebreakerId required');
  }
  if (action !== 'accept' && action !== 'decline') {
    throw new HttpsError('invalid-argument', "action must be 'accept' or 'decline'");
  }

  const icebreakerRef = db.collection('icebreakers').doc(icebreakerId);

  if (action === 'decline') {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(icebreakerRef);
      if (!snap.exists) throw new HttpsError('not-found', 'Icebreaker not found');
      const ib = snap.data()!;
      if (ib.recipientId !== uid) {
        throw new HttpsError('permission-denied', 'Not the recipient');
      }
      if (ib.status !== 'sent') {
        throw new HttpsError('failed-precondition', `Icebreaker is ${ib.status}, not sent`);
      }
      tx.update(icebreakerRef, {
        status: 'declined',
        declinedAt: FieldValue.serverTimestamp(),
      });
    });
    console.log(`[icebreaker-respond] ${icebreakerId} declined by ${uid}`);
    return { ok: true, action: 'declined' };
  }

  // Accept path — pre-allocate the meetup id so we can return it from the
  // transaction.  Firestore auto-ids are valid before the doc is written.
  const meetupRef = db.collection('meetups').doc();
  const meetupId = meetupRef.id;

  // Captured inside the transaction and returned to the client so the
  // recipient's in-memory LiveSession can mirror the new balance + reset
  // window without a second Firestore read.
  let returnedCredits = 0;
  let returnedResetAtMs: number | null = null;

  await db.runTransaction(async (tx) => {
    // ── 1. Icebreaker assertions ──────────────────────────────────────────────
    const ibSnap = await tx.get(icebreakerRef);
    if (!ibSnap.exists) throw new HttpsError('not-found', 'Icebreaker not found');
    const ib = ibSnap.data()!;
    if (ib.recipientId !== uid) {
      throw new HttpsError('permission-denied', 'Not the recipient');
    }
    if (ib.status !== 'sent') {
      throw new HttpsError('failed-precondition', `Icebreaker is ${ib.status}, not sent`);
    }
    const expiresAt = ib.expiresAt as Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError('failed-precondition', 'Icebreaker has expired');
    }
    const senderId = ib.senderId as string;
    const senderFirstName = (ib.senderFirstName as string | undefined) ?? '';
    const recipientFirstName = (ib.recipientFirstName as string | undefined) ?? '';

    // ── 2. Recipient credits + 24h reset ──────────────────────────────────────
    const recipientRef = db.collection('users').doc(uid);
    const recipientSnap = await tx.get(recipientRef);
    let credits =
      (recipientSnap.data()?.icebreakerCredits as number | undefined) ??
      FREE_ICEBREAKER_CREDITS;
    const storedResetAt = recipientSnap.data()?.icebreakerCreditsResetAt as
      | Timestamp
      | undefined;
    const nowMs = Date.now();
    const windowExpired = !!storedResetAt && nowMs > storedResetAt.toMillis();
    if (windowExpired) credits = FREE_ICEBREAKER_CREDITS;
    if (credits <= 0) {
      throw new HttpsError('failed-precondition', 'No icebreakers left');
    }
    const newCredits = credits - 1;
    const newResetAt =
      windowExpired || !storedResetAt
        ? Timestamp.fromMillis(nowMs + 24 * 3600 * 1000)
        : storedResetAt;

    // ── 3. Meetup-render photos + shared color ────────────────────────────────
    const [
      senderProfileSnap,
      recipientProfileSnap,
      senderLiveSessionSnap,
      recipientLiveSessionSnap,
    ] = await Promise.all([
      tx.get(db.collection('profiles').doc(senderId)),
      tx.get(db.collection('profiles').doc(uid)),
      tx.get(db.collection('live_sessions').doc(senderId)),
      tx.get(db.collection('live_sessions').doc(uid)),
    ]);
    const senderPhotoUrl = pickMeetupRenderPhoto(
      senderLiveSessionSnap.data(),
      senderProfileSnap.data(),
    );
    const recipientPhotoUrl = pickMeetupRenderPhoto(
      recipientLiveSessionSnap.data(),
      recipientProfileSnap.data(),
    );
    const matchColorHex = chooseMeetupMatchColorHex(meetupId);

    // ── 4. Writes ─────────────────────────────────────────────────────────────
    tx.update(recipientRef, {
      icebreakerCredits: newCredits,
      icebreakerCreditsResetAt: newResetAt,
    });
    returnedCredits = newCredits;
    returnedResetAtMs = newResetAt.toMillis();

    tx.set(meetupRef, {
      participants: [senderId, uid],
      participantNames: {
        [senderId]: senderFirstName,
        [uid]: recipientFirstName,
      },
      participantPhotos: {
        [senderId]: senderPhotoUrl,
        [uid]: recipientPhotoUrl,
      },
      matchColorHex,
      foundConfirmedBy: [],
      status: 'finding',
      icebreakerId: icebreakerId,
      createdAt: FieldValue.serverTimestamp(),
      // findExpiresAt is stamped by [onMeetupCreated] so the timer starts on
      // the trigger-fired write rather than at transaction-commit time.
    });

    tx.update(icebreakerRef, {
      status: 'accepted',
      meetupId: meetupId,
      acceptedAt: FieldValue.serverTimestamp(),
    });
  });

  console.log(`[icebreaker-respond] ${icebreakerId} accepted by ${uid} → meetup ${meetupId}`);
  return {
    ok: true,
    action: 'accepted',
    meetupId,
    // Authoritative post-decrement balance + window so the client mirror
    // (LiveSession.icebreakerCredits) stays in sync with Firestore.
    icebreakerCredits: returnedCredits,
    icebreakerCreditsResetAtMs: returnedResetAtMs,
  };
});

/**
 * onIcebreakerExpired — flips status='sent' to 'expired' once expiresAt has
 * passed.  Authoritative TTL writer; clients never write 'expired'.
 *
 * Runs every minute.  At icebreaker volume an upper bound of 100/run keeps the
 * function fast and bounded; if a backlog accumulates, subsequent runs drain
 * it.  No backfill state required — the where(status='sent', expiresAt<=now)
 * query is naturally idempotent.
 */
export const onIcebreakerExpired = onSchedule('every 1 minutes', async () => {
  const now = Timestamp.now();
  const snap = await db
    .collection('icebreakers')
    .where('status', '==', 'sent')
    .where('expiresAt', '<=', now)
    .limit(100)
    .get();
  if (snap.empty) return;
  const writer = db.bulkWriter();
  for (const doc of snap.docs) {
    writer.update(doc.ref, {
      status: 'expired',
      expiredAt: FieldValue.serverTimestamp(),
    });
  }
  await writer.close();
  console.log(`[icebreaker-expire] expired ${snap.size} icebreaker(s)`);
});

/**
 * onMeetupCreated — fires on the freshly-written meetup doc and:
 *   1. Stamps findExpiresAt = now + FIND_TIMER_SECONDS.  Clients never write
 *      this field; the rule layer (allow update only on foundConfirmedBy)
 *      already prevents that.  Stamping here makes the find timer's start
 *      point the trigger-fired write rather than the originating transaction
 *      commit, which keeps both clients' countdowns identical to the second.
 *   2. Writes users.{uid}.currentMeetupId = meetupId on both participants.
 *      LiveSession's existing _subscribeToMeetupMirror picks the field up and
 *      flips live_sessions.{uid}.visibilityState to 'hidden_in_meetup', which
 *      removes both users from Nearby discovery while the meetup is active.
 */
export const onMeetupCreated = onDocumentCreated(
  'meetups/{meetupId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const participants = (data.participants as string[] | undefined) ?? [];
    if (participants.length !== 2) {
      console.warn(
        `[meetup-created] ${snap.id} has ${participants.length} participants — skipping`,
      );
      return;
    }
    const findExpiresAt = Timestamp.fromMillis(Date.now() + FIND_TIMER_SECONDS * 1000);
    await Promise.all([
      snap.ref.update({ findExpiresAt }),
      db.collection('users').doc(participants[0]).update({ currentMeetupId: snap.id }),
      db.collection('users').doc(participants[1]).update({ currentMeetupId: snap.id }),
    ]);
    console.log(
      `[meetup-created] ${snap.id} stamped findExpiresAt + currentMeetupId on [${participants.join(', ')}]`,
    );
  },
);

/**
 * onMeetupTerminal — clears users.{uid}.currentMeetupId on both participants
 * when a meetup enters any [TERMINAL_MEETUP_STATUSES] state.
 *
 * Triggers on every meetup write but only acts when status changes INTO a
 * terminal value.  The before/after status comparison makes the function
 * idempotent — re-firing on the same terminal state is a no-op.
 *
 * Why guard on currentMeetupId equality before deleting: if the user has
 * already started a fresh meetup (rare race — rapid accept after cancel), we
 * don't want this CF clobbering the new meetupId.  Only clear when the field
 * still points at the meetup that just terminated.
 */
export const onMeetupTerminal = onDocumentWritten(
  'meetups/{meetupId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return; // delete — not used; rules forbid it anyway

    const beforeStatus = (before?.status as string | undefined) ?? '';
    const afterStatus = (after.status as string | undefined) ?? '';
    if (beforeStatus === afterStatus) return;
    if (!TERMINAL_MEETUP_STATUSES.has(afterStatus)) return;

    const participants = (after.participants as string[] | undefined) ?? [];
    if (participants.length !== 2) return;
    const meetupId = event.params.meetupId;

    await Promise.all(
      participants.map(async (uid) => {
        const userRef = db.collection('users').doc(uid);
        const userSnap = await userRef.get();
        const current = userSnap.data()?.currentMeetupId as string | undefined;
        if (current === meetupId) {
          await userRef.update({ currentMeetupId: FieldValue.delete() });
        }
      }),
    );
    console.log(
      `[meetup-terminal] ${meetupId}: ${beforeStatus} → ${afterStatus}; ` +
        `cleared currentMeetupId on [${participants.join(', ')}]`,
    );
  },
);

/**
 * onMeetupCancelRequestCreated — flips an active meetup to a phase-specific
 * cancelled_* terminal on the first cancelRequests subdoc.  Mirrors the
 * existing onEndRequestCreated pattern but covers both pre-talk phases:
 *
 *   finding → cancelled_finding   (exit before either user confirmed)
 *   talking → cancelled_talking   (exit during the 10-min talk timer)
 *
 * The phase guard is required because the cancelRequests rule only permits
 * creation while status is in ['finding', 'talking'], but races (a second
 * user tapping exit just after the schedule has flipped the meetup forward)
 * can still slip an extra subdoc through if the rule's get() reads stale
 * state.  Idempotency falls out of the guard.
 */
export const onFindingCancelRequestCreated = onDocumentCreated(
  'meetups/{meetupId}/cancelRequests/{uid}',
  async (event) => {
    const meetupId = event.params.meetupId;
    const uid = event.params.uid;
    const meetupRef = db.collection('meetups').doc(meetupId);
    const snap = await meetupRef.get();
    if (!snap.exists) return;
    const status = snap.data()?.status as string | undefined;
    if (status !== 'finding' && status !== 'talking') {
      console.log(
        `[meetup-cancel] ${meetupId}: already ${status} — ignoring cancel from ${uid}`,
      );
      return;
    }
    const newStatus =
      status === 'finding' ? 'cancelled_finding' : 'cancelled_talking';
    await meetupRef.update({
      status: newStatus,
      concludedAt: FieldValue.serverTimestamp(),
      cancelledBy: uid,
    });
    console.log(`[meetup-cancel] ${meetupId} → ${newStatus} by ${uid}`);
  },
);

/**
 * onMeetupFindingExpired — flips finding meetups to 'expired_finding' once
 * findExpiresAt has passed.  Authoritative timer expiry, by design:
 *
 *   The earlier plan considered an opportunistic client-side flip on
 *   countdown completion, but a sleeping or crashed peer would strand the
 *   other user in 'finding' indefinitely.  Server-owned expiry with a 1-min
 *   tick is bounded-latency and resilient to client outages.
 *
 * The downstream cascade (onMeetupTerminal → currentMeetupId clear → live
 * session visibilityState flip back to 'discoverable') is identical to every
 * other terminal status — no special-casing for expiry.
 */
export const onMeetupFindingExpired = onSchedule('every 1 minutes', async () => {
  const now = Timestamp.now();
  const snap = await db
    .collection('meetups')
    .where('status', '==', 'finding')
    .where('findExpiresAt', '<=', now)
    .limit(100)
    .get();
  if (snap.empty) return;
  const writer = db.bulkWriter();
  for (const doc of snap.docs) {
    writer.update(doc.ref, {
      status: 'expired_finding',
      concludedAt: FieldValue.serverTimestamp(),
    });
  }
  await writer.close();
  console.log(`[meetup-expire] expired ${snap.size} finding meetup(s)`);
});

/**
 * onMeetupFoundConfirmed — flips a 'finding' meetup to 'talking' once both
 * participants have appeared in foundConfirmedBy.  This is the missing
 * server-owned transition that the firestore.rules state-machine documentation
 * (finding → talking → awaiting_post_talk_decision) already assumes exists;
 * without it the meetup stays in 'finding' forever, currentMeetupId never
 * clears, and both users remain hidden from Nearby for the lifetime of the
 * find timer.
 *
 * Trigger semantics:
 *   • onDocumentWritten on `meetups/{id}` so we react to the foundConfirmedBy
 *     arrayUnion writes from each participant — there is no parent-doc trigger
 *     scoped to "field changed", so we filter inside the body.
 *   • Acts only when after.status === 'finding' AND both participants are in
 *     foundConfirmedBy.  Re-fires on any subsequent write are filtered by the
 *     status guard (after the first flip the status is 'talking', so we early
 *     return without doing further work).
 *
 * Race safety:
 *   • The actual flip runs inside a transaction that re-reads status and
 *     re-checks both UIDs.  Two concurrent invocations (one per
 *     foundConfirmedBy write, fired in lock-step on the same write) both read
 *     status==='finding' and try to commit; Firestore optimistic locking lets
 *     exactly one win.  The loser sees status==='talking' on retry and
 *     returns without writing.
 *
 * talkExpiresAt is stamped here so the conversation timer starts at the
 * trigger-fired write rather than at the originating arrayUnion — keeps both
 * clients' countdowns identical.
 */
export const onMeetupFoundConfirmed = onDocumentWritten(
  'meetups/{meetupId}',
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;
    if (after.status !== 'finding') return;

    const participants = (after.participants as string[] | undefined) ?? [];
    if (participants.length !== 2) return;

    const confirmed = (after.foundConfirmedBy as string[] | undefined) ?? [];
    const bothConfirmed = participants.every((p) => confirmed.includes(p));
    if (!bothConfirmed) return;

    const meetupId = event.params.meetupId;
    const meetupRef = db.collection('meetups').doc(meetupId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(meetupRef);
      if (!snap.exists) return;
      const data = snap.data()!;
      // Re-check inside the transaction so two concurrent invocations that
      // both saw status==='finding' do not both flip — the loser reads
      // 'talking' here and exits.
      if (data.status !== 'finding') return;
      const cBy = (data.foundConfirmedBy as string[] | undefined) ?? [];
      if (!participants.every((p) => cBy.includes(p))) return;

      const talkExpiresAt = Timestamp.fromMillis(
        Date.now() + TALK_TIMER_SECONDS * 1000,
      );
      tx.update(meetupRef, {
        status: 'talking',
        talkExpiresAt,
        talkingStartedAt: FieldValue.serverTimestamp(),
      });
    });

    console.log(`[meetup-found] ${meetupId} → talking`);
  },
);

/**
 * onMeetupTalkExpired — flips 'talking' meetups to 'awaiting_post_talk_decision'
 * once talkExpiresAt has passed, stamping decisionExpiresAt so the decision
 * window is itself bounded.
 *
 * This is the only path that lets clients submit decisions: firestore.rules
 * gates `meetups/{id}/decisions/{uid}` create on
 * status === 'awaiting_post_talk_decision', so any flip earlier or later is
 * an attempt that the rule would reject.  By owning the transition here we
 * keep the client's PostMeetScreen purely reactive (stream meetup status,
 * submit when status flips into the decision window).
 *
 * Latency: scheduled on a 1-min tick so a single user closing their app
 * doesn't strand the other in 'talking'.  Bounded above by `limit(100)` per
 * run to keep the function fast; subsequent runs drain any backlog.
 */
export const onMeetupTalkExpired = onSchedule('every 1 minutes', async () => {
  const now = Timestamp.now();
  const snap = await db
    .collection('meetups')
    .where('status', '==', 'talking')
    .where('talkExpiresAt', '<=', now)
    .limit(100)
    .get();
  if (snap.empty) return;
  const writer = db.bulkWriter();
  const decisionExpiresAt = Timestamp.fromMillis(
    Date.now() + DECISION_WINDOW_SECONDS * 1000,
  );
  for (const doc of snap.docs) {
    writer.update(doc.ref, {
      status: 'awaiting_post_talk_decision',
      decisionExpiresAt,
      talkEndedAt: FieldValue.serverTimestamp(),
    });
  }
  await writer.close();
  console.log(
    `[meetup-talk-expired] flipped ${snap.size} meetup(s) → awaiting_post_talk_decision`,
  );
});

/**
 * onTalkExpiredRequestCreated — client-driven counterpart to the every-1-min
 * onMeetupTalkExpired scheduler.  Either client writes a subdoc the moment
 * its local talk timer hits 0; this trigger flips the meetup forward
 * immediately so the user can submit a decision without waiting up to ~60 s
 * for the next scheduler tick.
 *
 * Why both:
 *   • The scheduler stays as the authoritative backstop — if both apps are
 *     closed when the timer expires, we still flip the meetup forward and
 *     onMeetupDecisionExpired can collapse it into 'no_match'.
 *   • The trigger removes the dead-air spinner the user reported when they
 *     tap a decision button at 0:00 and the rule denies the write because
 *     status hasn't flipped yet.
 *
 * Idempotency: re-checks status === 'talking' inside the handler, so a
 * second client's request after the first flip is a no-op.  Re-uses the
 * same DECISION_WINDOW_SECONDS to stamp decisionExpiresAt so the decision
 * window length is identical regardless of which path flipped the status.
 *
 * Defence in depth: also re-checks talkExpiresAt is in the past — guards
 * against a client whose clock is far ahead of server time triggering an
 * early flip.  A clock-drifted client will simply see its request go
 * through ~no-op, and the scheduler will fire when the real moment lands.
 */
export const onTalkExpiredRequestCreated = onDocumentCreated(
  'meetups/{meetupId}/talkExpiredRequests/{uid}',
  async (event) => {
    const meetupId = event.params.meetupId;
    const uid = event.params.uid;
    const meetupRef = db.collection('meetups').doc(meetupId);
    const snap = await meetupRef.get();
    if (!snap.exists) return;
    const data = snap.data()!;
    const status = data.status as string | undefined;
    if (status !== 'talking') {
      console.log(
        `[meetup-talk-expired-req] ${meetupId}: already ${status} — ignoring from ${uid}`,
      );
      return;
    }
    const talkExpiresAt = data.talkExpiresAt as Timestamp | undefined;
    if (talkExpiresAt && talkExpiresAt.toMillis() > Date.now()) {
      console.log(
        `[meetup-talk-expired-req] ${meetupId}: talkExpiresAt still in future — ignoring from ${uid}`,
      );
      return;
    }
    const decisionExpiresAt = Timestamp.fromMillis(
      Date.now() + DECISION_WINDOW_SECONDS * 1000,
    );
    await meetupRef.update({
      status: 'awaiting_post_talk_decision',
      decisionExpiresAt,
      talkEndedAt: FieldValue.serverTimestamp(),
    });
    console.log(
      `[meetup-talk-expired-req] ${meetupId} → awaiting_post_talk_decision via ${uid}`,
    );
  },
);

/**
 * onMeetupDecisionExpired — guarantees a meetup never stalls in
 * 'awaiting_post_talk_decision' if one or both users never submit.
 *
 * Without this, a user who never opens the post-meet screen would leave the
 * other in a permanently-hidden state (currentMeetupId never clears, and
 * therefore live_sessions.visibilityState stays 'hidden_in_meetup'). This
 * was the literal failure mode the original "both phones live but Nearby is
 * empty" report described, just one phase further along the state machine
 * than the foundConfirmed gap was.
 *
 * Treats decision-window expiry as no_match: the user who DID submit
 * 'we_got_this' would have wanted a chat to open, but only opens with
 * mutual yes — and the ghosting peer didn't deliver one.  Folding into
 * no_match keeps TERMINAL_MEETUP_STATUSES tight and reuses the existing
 * onMeetupTerminal cascade (currentMeetupId clear → discoverable).
 *
 * `expiredReason` is left as a breadcrumb for telemetry; clients ignore it.
 */
export const onMeetupDecisionExpired = onSchedule(
  'every 1 minutes',
  async () => {
    const now = Timestamp.now();
    const snap = await db
      .collection('meetups')
      .where('status', '==', 'awaiting_post_talk_decision')
      .where('decisionExpiresAt', '<=', now)
      .limit(100)
      .get();
    if (snap.empty) return;
    const writer = db.bulkWriter();
    for (const doc of snap.docs) {
      writer.update(doc.ref, {
        status: 'no_match',
        concludedAt: FieldValue.serverTimestamp(),
        expiredReason: 'decision_window_elapsed',
      });
    }
    await writer.close();
    console.log(
      `[meetup-decision-expired] flipped ${snap.size} meetup(s) → no_match`,
    );
  },
);
