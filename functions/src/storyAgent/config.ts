import { defineSecret, defineString } from "firebase-functions/params";

// Secrets (set via: firebase functions:secrets:set <NAME>)
export const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
export const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");
export const STORY_AGENT_SECRET = defineSecret("STORY_AGENT_SECRET");

// Params (set via .env or --set during deploy)
export const STORY_APPROVAL_EMAIL = defineString("STORY_APPROVAL_EMAIL", {
  default: "moresunilkumar@gmail.com",
  description: "Recipient for daily story-approval emails",
});
export const STORY_FROM_EMAIL = defineString("STORY_FROM_EMAIL", {
  default: "no-reply@suzyapp.app",
  description: "Verified SendGrid sender address",
});

export const PROJECT_ID = process.env.GCLOUD_PROJECT || "suzyapp";
export const APPROVE_FUNCTION_URL = `https://us-central1-${PROJECT_ID}.cloudfunctions.net/storyApprove`;

export const PROPOSALS_COLLECTION = "story_proposals";
export const STORIES_COLLECTION = "stories";

// Approval links stay valid for 7 days.
export const APPROVAL_TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
