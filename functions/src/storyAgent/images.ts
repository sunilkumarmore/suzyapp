import * as admin from "firebase-admin";
import { getDownloadURL } from "firebase-admin/storage";
import { GoogleAuth } from "google-auth-library";
import fetch from "node-fetch";
import { PROJECT_ID } from "./config";

// Imagen 3 via Vertex AI. Uses the function's own service account (ADC) —
// requires the "Vertex AI User" role on the runtime service account.

const IMAGEN_MODEL = "imagen-3.0-generate-002";
const VERTEX_URL =
  `https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}` +
  `/locations/us-central1/publishers/google/models/${IMAGEN_MODEL}:predict`;

const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

async function generateImageBase64(
  prompt: string,
  aspectRatio: "1:1" | "4:3"
): Promise<string | null> {
  try {
    const authClient = await auth.getClient();
    const accessToken = (await authClient.getAccessToken()).token;
    if (!accessToken) return null;

    const resp = await fetch(VERTEX_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
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
  prompt: string,
  storagePath: string,
  aspectRatio: "1:1" | "4:3" = "4:3"
): Promise<string | null> {
  const base64 = await generateImageBase64(prompt, aspectRatio);
  if (!base64) return null;
  return uploadPng(base64, storagePath);
}
