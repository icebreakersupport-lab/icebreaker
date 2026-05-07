/**
 * One-shot backfill for the meetupOutcome backref added in onMeetupTerminal.
 *
 * Iterates every meetup whose status is in TERMINAL_MEETUP_STATUSES and
 * writes (meetupOutcome, meetupConcludedAt) onto the icebreaker referenced
 * by `meetups/{id}.icebreakerId`.  Idempotent — re-running is safe; each
 * write is a plain `update()` with the same payload.
 *
 * Run once after deploying the onMeetupTerminal change:
 *
 *   1. Download a service account key from Firebase Console →
 *      Project Settings → Service Accounts → Generate New Private Key.
 *      Save the JSON to functions/.serviceAccountKey.json.
 *      (The file is gitignored — never commit it.)
 *
 *   2. From the project root:
 *        cd functions
 *        npx ts-node scripts/backfill_meetup_outcomes.ts
 *
 *   3. The script logs how many meetups it scanned, how many backrefs it
 *      wrote, and how many were skipped (no icebreakerId, or icebreaker
 *      doc missing).  Remove .serviceAccountKey.json afterwards if you
 *      don't plan to run other admin scripts.
 */
import * as path from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const SERVICE_ACCOUNT_PATH = path.resolve(
  __dirname,
  '..',
  '.serviceAccountKey.json',
);

const TERMINAL_MEETUP_STATUSES: ReadonlySet<string> = new Set([
  'matched',
  'ended',
  'no_match',
  'expired_finding',
  'cancelled_finding',
  'cancelled_talking',
]);

async function main() {
  initializeApp({ credential: cert(SERVICE_ACCOUNT_PATH) });
  const db = getFirestore();

  let scanned = 0;
  let wrote = 0;
  let skippedNoIcebreaker = 0;
  let skippedMissingIcebreaker = 0;
  let alreadySet = 0;
  let errors = 0;

  // No composite index needed — we scan all meetups and filter client-side.
  // At early-stage volume this is cheap; at scale, swap in an indexed query.
  const snap = await db.collection('meetups').get();
  console.log(`[backfill] scanning ${snap.size} meetup(s)…`);

  for (const doc of snap.docs) {
    scanned += 1;
    const data = doc.data();
    const status = data.status as string | undefined;
    if (!status || !TERMINAL_MEETUP_STATUSES.has(status)) continue;

    const icebreakerId = (data.icebreakerId as string | undefined) ?? '';
    if (!icebreakerId) {
      skippedNoIcebreaker += 1;
      continue;
    }

    const ibRef = db.collection('icebreakers').doc(icebreakerId);
    const ibSnap = await ibRef.get();
    if (!ibSnap.exists) {
      skippedMissingIcebreaker += 1;
      continue;
    }

    // Skip ones that already have a meetupOutcome set — likely written by
    // the live CF after deploy.  Cheap idempotency guard.
    const existing = ibSnap.data()?.meetupOutcome as string | undefined;
    if (existing === status) {
      alreadySet += 1;
      continue;
    }

    try {
      // Use the meetup's own concludedAt / matchedAt / decisionExpiresAt
      // when available so the backfilled timestamp matches the real conclusion
      // moment, not the moment we ran this script.  Falls back to serverTime
      // for legacy meetups missing every timestamp field.
      const concludedAt =
        data.concludedAt ?? data.matchedAt ?? FieldValue.serverTimestamp();
      await ibRef.update({
        meetupOutcome: status,
        meetupConcludedAt: concludedAt,
      });
      wrote += 1;
    } catch (err) {
      errors += 1;
      console.warn(
        `[backfill] FAILED to update icebreaker ${icebreakerId} ` +
          `(meetup ${doc.id}):`,
        err,
      );
    }
  }

  console.log('[backfill] done');
  console.log(`  scanned:                    ${scanned}`);
  console.log(`  wrote:                      ${wrote}`);
  console.log(`  already set (no-op):        ${alreadySet}`);
  console.log(`  skipped (no icebreakerId):  ${skippedNoIcebreaker}`);
  console.log(`  skipped (missing icebreaker): ${skippedMissingIcebreaker}`);
  console.log(`  errors:                     ${errors}`);
}

main().catch((err) => {
  console.error('[backfill] fatal:', err);
  process.exit(1);
});
