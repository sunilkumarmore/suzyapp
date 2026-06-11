# Suzy Story Agent

Automated daily story pipeline:

```
Cloud Scheduler (8 AM)
    → storyProposalDaily      Claude generates 3 proposals (1 EN + 2 TE)
                              Imagen generates a character sketch each
                              SendGrid emails them with Approve/Skip buttons
    → storyApprove            (HTTPS) verifies the HMAC link, flips status
    → storyCompleteOnApproval (Firestore trigger) Claude writes the full story,
                              Imagen illustrates every page, publishes /stories/{id}
```

Stories land in the `stories` collection in exactly the shape
`FirestoreStoryRepository` expects (`title`, `language`, `ageBand`, `coverUrl`,
`pages[].text/backgroundUrl/emotionEmoji`) — no app changes required.
Narration audio is generated on demand by the existing `generateNarration`
function when a child opens the story.

## One-time setup

1. **Secrets**
   ```sh
   firebase functions:secrets:set ANTHROPIC_API_KEY     # console.anthropic.com
   firebase functions:secrets:set SENDGRID_API_KEY      # app.sendgrid.com
   firebase functions:secrets:set STORY_AGENT_SECRET    # any long random string, e.g. `openssl rand -hex 32`
   ```

2. **Params** — set in `functions/.env` (or accept defaults):
   ```
   STORY_APPROVAL_EMAIL=moresunilkumar@gmail.com
   STORY_FROM_EMAIL=no-reply@suzyapp.app   # must be a verified SendGrid sender
   ```

3. **SendGrid** — verify the sender address (Single Sender Verification or
   domain authentication) or every send returns 403.

4. **Vertex AI (Imagen)** — enable the Vertex AI API on the `suzyapp` project
   and grant the functions' runtime service account the **Vertex AI User**
   role. If image generation fails the pipeline still completes — stories
   publish without illustrations and the app shows its gradient fallback.

5. **Timezone** — the schedule is `0 8 * * *` in `America/Chicago`; edit
   `storyAgent.ts` if mornings should follow a different timezone.

## Deploy

```sh
firebase deploy --only functions:storyProposalDaily,functions:storyApprove,functions:storyCompleteOnApproval
```

## Manually trigger a test run

```sh
gcloud scheduler jobs run firebase-schedule-storyProposalDaily-us-central1 --project suzyapp
```

## Data model

`story_proposals/{id}`: proposal fields + `status`
(`pending → approved|rejected → generating → published|failed`), `sketchUrl`,
`storyId` once published, `error` on failure. Clients have no access (rules
deny by default); only the Admin SDK touches it.

## Cost notes

- Claude (Opus 4.8): one proposal call + one full-story call per approved
  story — roughly a few cents/day.
- Imagen 3: ~$0.04/image → a 10-page story ≈ $0.45. The largest cost lever;
  reduce by illustrating only odd pages if needed.
