import Anthropic from "@anthropic-ai/sdk";
import { STORY_STUDIO_SYSTEM_PROMPT, buildProposalsUserPrompt, buildFullStoryUserPrompt } from "./prompts";
import { proposalsSchema, fullStorySchema, StoryProposal, GeneratedStory } from "./schemas";

const MODEL = "claude-sonnet-4-6";

function client(apiKey: string): Anthropic {
  return new Anthropic({ apiKey });
}

// Shared, cached system block. The breakpoint caches the system prompt across
// the proposal and full-story calls. Note: caching only activates once the
// prefix exceeds the model's minimum cacheable length; below that it is
// silently skipped, which is harmless.
const SYSTEM = [
  {
    type: "text" as const,
    text: STORY_STUDIO_SYSTEM_PROMPT,
    cache_control: { type: "ephemeral" as const },
  },
];

function extractJson<T>(message: Anthropic.Message): T {
  if (message.stop_reason === "refusal") {
    throw new Error("Claude refused the request (stop_reason: refusal)");
  }
  if (message.stop_reason === "max_tokens") {
    throw new Error("Claude output truncated (stop_reason: max_tokens)");
  }
  const text = message.content.find(
    (b): b is Anthropic.TextBlock => b.type === "text"
  )?.text;
  if (!text) {
    throw new Error("No text block in Claude response");
  }
  return JSON.parse(text) as T;
}

export async function generateProposals(
  apiKey: string,
  recentTitles: string[]
): Promise<StoryProposal[]> {
  const response = await client(apiKey).messages.create({
    model: MODEL,
    max_tokens: 16000,
    thinking: { type: "adaptive" },
    system: SYSTEM,
    messages: [{ role: "user", content: buildProposalsUserPrompt(recentTitles) }],
    output_config: {
      format: { type: "json_schema", schema: proposalsSchema as unknown as Record<string, unknown> },
    },
  });

  const parsed = extractJson<{ proposals: StoryProposal[] }>(response);
  if (!Array.isArray(parsed.proposals) || parsed.proposals.length !== 3) {
    throw new Error(`Expected 3 proposals, got ${parsed.proposals?.length ?? 0}`);
  }
  return parsed.proposals;
}

export async function generateFullStory(
  apiKey: string,
  proposal: StoryProposal
): Promise<GeneratedStory> {
  // Full stories are long — stream to avoid HTTP timeouts at high max_tokens.
  const stream = client(apiKey).messages.stream({
    model: MODEL,
    max_tokens: 64000,
    thinking: { type: "adaptive" },
    system: SYSTEM,
    messages: [{ role: "user", content: buildFullStoryUserPrompt(proposal) }],
    output_config: {
      format: { type: "json_schema", schema: fullStorySchema as unknown as Record<string, unknown> },
    },
  });

  const message = await stream.finalMessage();
  const story = extractJson<GeneratedStory>(message);
  if (!Array.isArray(story.pages) || story.pages.length < 4) {
    throw new Error(`Story has too few pages: ${story.pages?.length ?? 0}`);
  }
  return story;
}
