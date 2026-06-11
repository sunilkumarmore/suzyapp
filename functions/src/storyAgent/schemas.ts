// JSON schemas for Claude structured outputs (output_config.format).
// Constraints: every object needs additionalProperties:false; no minItems/
// maxLength-style constraints (enforced via the prompt instead).

export const proposalsSchema = {
  type: "object",
  properties: {
    proposals: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          language: { type: "string", enum: ["en", "te"] },
          ageBand: { type: "string", enum: ["2-3", "4-5", "6-7"] },
          premise: {
            type: "string",
            description: "Two-sentence story premise a parent can evaluate at a glance",
          },
          heroName: { type: "string" },
          heroDescription: {
            type: "string",
            description: "Personality + visual description of the main character",
          },
          heroSketchPrompt: {
            type: "string",
            description:
              "Image-generation prompt for a character sketch: the hero alone, " +
              "full body, friendly children's storybook style, plain white background",
          },
          setting: { type: "string" },
          moral: { type: "string", description: "The gentle lesson of the story" },
        },
        required: [
          "title",
          "language",
          "ageBand",
          "premise",
          "heroName",
          "heroDescription",
          "heroSketchPrompt",
          "setting",
          "moral",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["proposals"],
  additionalProperties: false,
} as const;

export const fullStorySchema = {
  type: "object",
  properties: {
    title: { type: "string" },
    language: { type: "string", enum: ["en", "te"] },
    ageBand: { type: "string", enum: ["2-3", "4-5", "6-7"] },
    coverScenePrompt: {
      type: "string",
      description: "Image-generation prompt for the story cover illustration",
    },
    pages: {
      type: "array",
      items: {
        type: "object",
        properties: {
          text: { type: "string", description: "The page text shown to the child" },
          scenePrompt: {
            type: "string",
            description:
              "Self-contained image-generation prompt for this page's full-scene " +
              "illustration. Must re-describe the hero's appearance verbatim on every " +
              "page so the character stays visually consistent.",
          },
          emotionEmoji: {
            type: "string",
            description: "Single emoji matching the page's mood, e.g. \u{1F60A}",
          },
        },
        required: ["text", "scenePrompt", "emotionEmoji"],
        additionalProperties: false,
      },
    },
  },
  required: ["title", "language", "ageBand", "coverScenePrompt", "pages"],
  additionalProperties: false,
} as const;

export interface StoryProposal {
  title: string;
  language: "en" | "te";
  ageBand: "2-3" | "4-5" | "6-7";
  premise: string;
  heroName: string;
  heroDescription: string;
  heroSketchPrompt: string;
  setting: string;
  moral: string;
}

export interface GeneratedPage {
  text: string;
  scenePrompt: string;
  emotionEmoji: string;
}

export interface GeneratedStory {
  title: string;
  language: "en" | "te";
  ageBand: "2-3" | "4-5" | "6-7";
  coverScenePrompt: string;
  pages: GeneratedPage[];
}
