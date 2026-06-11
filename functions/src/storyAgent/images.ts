import * as admin from "firebase-admin";
import { getDownloadURL } from "firebase-admin/storage";
import fetch from "node-fetch";

// Imagen 3 via the Gemini API (generativelanguage.googleapis.com).
// Uses a plain API key from Google AI Studio — free tier supports up to
// 1,500 requests/day, which covers all daily sketches + full story illustrations.
// Get a key at: https://aistudio.google.com/apikey

const IMAGEN_MODEL = "imagen-3.0-generate-002";
const GEMINI_IMAGEN_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${IMAGEN_MODEL}:predict`;

async function generateImageBase64(
  apiKey: string,
  prompt: string,
  aspectRatio: "1:1" | "4:3"
): Promise<string | null> {
  try {
    const resp = await fetch(`${GEMINI_IMAGEN_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        instances: [{ prompt }],
        parameters: {
          sampleCount: 1,
          aspectRatio,
          safetySetting: "block_low_and_above",
          personGeneration: "allow_all",
        },
      }),
    });

    if (!resp.ok) {
      console.error(`Imagen error ${resp.status}: ${(await resp.text()).slice(0, 500)}`);
      return null;
    }
    const data = (await resp.json()) as {
      predictions?: Array<{ bytesBase64Encoded?: string }>;
    };
    return data.predictions?.[0]?.bytesBase64Encoded ?? null;
  } catch (e) {
    console.error("Imagen request failed:", e);
    return null;
  }
}

async function uploadPng(base64: string, storagePath: string): Promise<string | null> {
  try {
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    await file.save(Buffer.from(base64, "base64"), {
      contentType: "image/png",
      metadata: { cacheControl: "public, max-age=31536000" },
    });
    return await getDownloadURL(file);
  } catch (e) {
    console.error(`Upload failed for ${storagePath}:`, e);
    return null;
  }
}

/**
 * Generates an illustration and uploads it to Storage.
 * Returns a download URL, or null on any failure — story generation should
 * continue without the image (the app renders a gradient fallback).
 */
export async function generateAndUploadImage(
  apiKey: string,
  prompt: string,
  storagePath: string,
  aspectRatio: "1:1" | "4:3" = "4:3"
): Promise<string | null> {
  const base64 = await generateImageBase64(apiKey, prompt, aspectRatio);
  if (!base64) return null;
  return uploadPng(base64, storagePath);
}
