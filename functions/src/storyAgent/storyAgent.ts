import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

import {
  ANTHROPIC_API_KEY,
  GEMINI_API_KEY,
  SENDGRID_API_KEY,
  STORY_AGENT_SECRET,
  STORY_APPROVAL_EMAIL,
  STORY_FROM_EMAIL,
  PROPOSALS_COLLECTION,
  STORIES_COLLECTION,
  APPROVAL_TOKEN_TTL_MS,
} from "./config";
import { generateProposals, generateFullStory } from "./claude";
import { generateAndUploadImage } from "./images";
import {
  buildApprovalUrl,
  buildProposalEmailHtml,
  sendEmail,
  ProposalEmailItem,
} from "./mailer";
import { createApprovalToken, verifyApprovalToken } from "./tokens";
import { StoryProposal } from "./schemas";

const db = () => admin.firestore();

// ---------------------------------------------------------------------------
// 1) Daily proposal run — 8:00 AM, emails 3 proposals (1 EN + 2 TE) with
//    character sketches and approve/skip links.
// ---------------------------------------------------------------------------
export const storyProposalDaily = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/Chicago", // adjust to your local timezone
    secrets: [ANTHROPIC_API_KEY, GEMINI_API_KEY, SENDGRID_API_KEY, STORY_AGENT_SECRET],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    // Recent titles → avoid repeating themes day after day.
    const recentSnap = await db()
      .collection(PROPOSALS_COLLECTION)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();
    const recentTitles = recentSnap.docs
      .map((d) => d.get("title") as string | undefined)
      .filter((t): t is string => typeof t === "string" && t.length > 0);

    const proposals = await generateProposals(ANTHROPIC_API_KEY.value(), recentTitles);

    const expiresAtMs = Date.now() + APPROVAL_TOKEN_TTL_MS;
    const items: ProposalEmailItem[] = [];

    for (const proposal of proposals) {
      const ref = db().collection(PROPOSALS_COLLECTION).doc();

      // Character sketch (best effort — email goes out without it on failure).
      const sketchUrl = await generateAndUploadImage(
        GEMINI_API_KEY.value(),
        proposal.heroSketchPrompt,
        `story_agent/proposals/${ref.id}/sketch.png`,
        "1:1"
      );

      await ref.set({
        ...proposal,
        sketchUrl,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        tokenExpiresAtMs: expiresAtMs,
      });

      const secret = STORY_AGENT_SECRET.value();
      items.push({
        proposalId: ref.id,
        proposal,
        sketchUrl,
        approveUrl: buildApprovalUrl(
          ref.id,
          "approve",
          expiresAtMs,
          createApprovalToken(secret, ref.id, "approve", expiresAtMs)
        ),
        rejectUrl: buildApprovalUrl(
          ref.id,
          "reject",
          expiresAtMs,
          createApprovalToken(secret, ref.id, "reject", expiresAtMs)
        ),
      });
    }

    const dateLabel = new Date().toLocaleDateString("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
    });
    await sendEmail(
      SENDGRID_API_KEY.value(),
      STORY_APPROVAL_EMAIL.value(),
      STORY_FROM_EMAIL.value(),
      `\u{1F4DA} 3 new Suzy stories for approval — ${dateLabel}`,
      buildProposalEmailHtml(items, dateLabel)
    );

    console.log(`Sent ${items.length} proposals to ${STORY_APPROVAL_EMAIL.value()}`);
  }
);

// ---------------------------------------------------------------------------
// 2) Approval endpoint — clicked from the email. Verifies the HMAC token and
//    flips the proposal status; the Firestore trigger picks it up from there.
// ---------------------------------------------------------------------------
export const storyApprove = onRequest(
  { secrets: [STORY_AGENT_SECRET] },
  async (req, res) => {
    const id = String(req.query.id ?? "");
    const action = String(req.query.action ?? "");
    const exp = Number(req.query.exp ?? 0);
    const token = String(req.query.token ?? "");

    const page = (title: string, body: string, ok: boolean) =>
      `<!DOCTYPE html><html><body style="font-family:Georgia,serif;background:#faf6ee;text-align:center;padding:60px 20px;">
       <h1 style="color:${ok ? "#4caf50" : "#c0392b"};">${title}</h1>
       <p style="color:#666;font-size:18px;">${body}</p></body></html>`;

    if (!id || !verifyApprovalToken(STORY_AGENT_SECRET.value(), id, action, exp, token)) {
      res.status(403).send(page("Link invalid or expired", "Request a fresh proposal email.", false));
      return;
    }

    const ref = db().collection(PROPOSALS_COLLECTION).doc(id);
    const snap = await ref.get();
    if (!snap.exists) {
      res.status(404).send(page("Proposal not found", "It may have been removed.", false));
      return;
    }

    const status = snap.get("status") as string;
    if (status !== "pending") {
      res
        .status(200)
        .send(page("Already handled", `This proposal is already "${status}".`, true));
      return;
    }

    if (action === "approve") {
      await ref.update({
        status: "approved",
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      res.send(
        page(
          "✓ Approved!",
          `"${snap.get("title")}" is being written and illustrated now. ` +
            "It will appear in the app in a few minutes.",
          true
        )
      );
    } else {
      await ref.update({
        status: "rejected",
        rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      res.send(page("Skipped", `"${snap.get("title")}" won't be produced.`, true));
    }
  }
);

// ---------------------------------------------------------------------------
// 3) Story completion — fires when a proposal flips to "approved". Writes the
//    full story, illustrates every page, and publishes to /stories.
// ---------------------------------------------------------------------------
export const storyCompleteOnApproval = onDocumentUpdated(
  {
    document: `${PROPOSALS_COLLECTION}/{proposalId}`,
    secrets: [ANTHROPIC_API_KEY, GEMINI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (after.status !== "approved" || before.status === "approved") return;

    const proposalId = event.params.proposalId;
    const ref = db().collection(PROPOSALS_COLLECTION).doc(proposalId);

    // Claim the work atomically so retries / double triggers don't duplicate.
    const claimed = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.get("status") !== "approved") return false;
      tx.update(ref, { status: "generating" });
      return true;
    });
    if (!claimed) return;

    try {
      const proposal = after as unknown as StoryProposal;
      const story = await generateFullStory(ANTHROPIC_API_KEY.value(), proposal);

      const storyRef = db().collection(STORIES_COLLECTION).doc();
      const storyId = storyRef.id;

      // Cover + one full-scene illustration per page (best effort each).
      const coverUrl = await generateAndUploadImage(
        GEMINI_API_KEY.value(),
        story.coverScenePrompt,
        `story_agent/stories/${storyId}/cover.png`,
        "4:3"
      );

      const pages: Array<Record<string, unknown>> = [];
      for (let i = 0; i < story.pages.length; i++) {
        const p = story.pages[i];
        const backgroundUrl = await generateAndUploadImage(
          GEMINI_API_KEY.value(),
          p.scenePrompt,
          `story_agent/stories/${storyId}/page_${i}.png`,
          "4:3"
        );
        pages.push({
          text: p.text,
          emotionEmoji: p.emotionEmoji,
          ...(backgroundUrl ? { backgroundUrl } : {}),
        });
      }

      await storyRef.set({
        id: storyId,
        title: story.title,
        language: story.language,
        ageBand: story.ageBand,
        ...(coverUrl ? { coverUrl } : {}),
        pages,
        source: "story_agent",
        proposalId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await ref.update({
        status: "published",
        storyId,
        publishedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Published story ${storyId} ("${story.title}") from proposal ${proposalId}`);
    } catch (e) {
      console.error(`Story generation failed for proposal ${proposalId}:`, e);
      await ref.update({
        status: "failed",
        error: String(e).slice(0, 1000),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);
