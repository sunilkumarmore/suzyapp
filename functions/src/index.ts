import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getAuth } from "firebase-admin/auth";
import FormData from "form-data";
import fetch from "node-fetch";

admin.initializeApp();

// ✅ Use Firebase Secrets properly for v2
const ELEVENLABS_KEY = defineSecret("ELEVENLABS_KEY");

async function verifyFirebaseAuth(req: any): Promise<string> {
  const authHeader = req.headers.authorization || "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    const err: any = new Error("Missing bearer token");
    err.status = 401;
    throw err;
  }

  const idToken = match[1];
  try {
    const decoded = await getAuth().verifyIdToken(idToken);
    return decoded.uid;
  } catch (e) {
    const err: any = new Error("Invalid token");
    err.status = 401;
    throw err;
  }
}

function normalizeLang(lang: any): "en" | "te" | null {
  if (typeof lang !== "string") return null;
  const l = lang.trim().toLowerCase();
  if (l === "en" || l === "te") return l;
  return null;
}

async function rateLimit(uid: string, key: string, windowMs: number, maxReq: number) {
  const ref = admin.firestore().doc(`users/${uid}/rate_limits/${key}`);
  const now = Date.now();

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data()! : {};
    const resetAt = typeof data.resetAt === "number" ? data.resetAt : 0;
    const count = typeof data.count === "number" ? data.count : 0;

    if (resetAt > now) {
      if (count >= maxReq) {
        const err: any = new Error("Too many requests");
        err.status = 429;
        throw err;
      }
      tx.set(ref, { count: count + 1 }, { merge: true });
    } else {
      tx.set(ref, { count: 1, resetAt: now + windowMs }, { merge: true });
    }
  });
}


export const generateNarration = onRequest(
  {
    cors: true,
    timeoutSeconds: 300,
    secrets: [ELEVENLABS_KEY],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Methods", "POST");
      res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
      res.set("Access-Control-Max-Age", "3600");
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      const uid = await verifyFirebaseAuth(req);
      await rateLimit(uid, "generateNarration", 60 * 1000, 10);

      const body = req.body ?? {};
      const { storyId, pageIndex, lang, text, voiceId } = body;

      if (typeof storyId !== "string" || storyId.trim().length === 0) {
        res.status(400).json({ error: "Invalid storyId" });
        return;
      }

      const pageIdxNum = Number(pageIndex);
      if (!Number.isInteger(pageIdxNum) || pageIdxNum < 0 || pageIdxNum > 500) {
        res.status(400).json({ error: "Invalid pageIndex" });
        return;
      }

      const normLang = normalizeLang(lang);
      if (!normLang) {
        res.status(400).json({ error: "Invalid lang (must be 'en' or 'te')" });
        return;
      }

      if (typeof voiceId !== "string" || voiceId.trim().length < 3) {
        res.status(400).json({ error: "Invalid voiceId" });
        return;
      }

      if (typeof text !== "string") {
        res.status(400).json({ error: "Invalid text" });
        return;
      }

      const cleanText = text.trim();
      if (cleanText.length === 0) {
        res.status(400).json({ error: "Empty text" });
        return;
      }

      if (cleanText.length > 1000) {
        res.status(413).json({ error: "Text too long (max 1000 chars)" });
        return;
      }

      const elevenKey = ELEVENLABS_KEY.value();
      if (!elevenKey) {
        res.status(500).json({ error: "Server not configured (missing ELEVENLABS_KEY)" });
        return;
      }

      const personalizedDoc = admin
        .firestore()
        .doc(`users/${uid}/personalized_audio/${storyId.trim()}`);
      const personalizedSnap = await personalizedDoc.get();
      if (personalizedSnap.exists) {
        const data = personalizedSnap.data() || {};
        const pages = (data.pages ?? {}) as Record<string, any>;
        const existing = pages[String(pageIdxNum)]?.audioUrl;
        if (typeof existing === "string" && existing.length > 0) {
          res.json({ audioUrl: existing, cached: true });
          return;
        }
      }

      const ttsResp = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId.trim()}`, {
        method: "POST",
        headers: {
          "xi-api-key": elevenKey,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
        body: JSON.stringify({
          text: cleanText,
          model_id: "eleven_multilingual_v2",
          voice_settings: { stability: 0.4, similarity_boost: 0.75 },
        }),
      });

      if (!ttsResp.ok) {
        const detail = await ttsResp.text();
        res.status(502).json({ error: "ElevenLabs TTS failed", detail });
        return;
      }

      const audioBuffer = Buffer.from(await ttsResp.arrayBuffer());
      if (audioBuffer.length < 200) {
        res.status(502).json({ error: "Invalid audio returned from ElevenLabs" });
        return;
      }

      const bucket = admin.storage().bucket();
      const storagePath = `users/${uid}/personalized_audio/${storyId.trim()}/page_${pageIdxNum}_${normLang}.mp3`;
      const file = bucket.file(storagePath);

      await file.save(audioBuffer, { contentType: "audio/mpeg" });

      const [signedUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
      });

      const pageKey = `pages.${pageIdxNum}.audioUrl`;
      await personalizedDoc.set(
        {
          storyId: storyId.trim(),
          lang: normLang,
          voiceId: voiceId.trim(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          [pageKey]: signedUrl,
        },
        { merge: true }
      );

      res.json({ audioUrl: signedUrl, cached: false });
    } catch (e: any) {
      const status = typeof e?.status === "number" ? e.status : 500;
      console.error("Error in generateNarration:", e);
      res.status(status).json({ error: e?.message || "Server error" });
    }
  }
);

export const parentVoiceCreate = onRequest(
  {
    cors: true,
    timeoutSeconds: 300,
    secrets: [ELEVENLABS_KEY],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Methods", "POST");
      res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
      res.set("Access-Control-Max-Age", "3600");
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    try {
      const uid = await verifyFirebaseAuth(req);
      console.log("parentVoiceCreate uid", uid);
      await rateLimit(uid, "parentVoiceCreate", 60 * 60 * 1000, 3);

      const body = req.body ?? {};
      const { audioBase64, mimeType, name } = body;
      console.log("parentVoiceCreate body", {
        hasAudioBase64: typeof audioBase64 === "string" && audioBase64.length > 0,
        audioLen: typeof audioBase64 === "string" ? audioBase64.length : 0,
        mimeType,
        name,
      });

      if (typeof audioBase64 !== "string" || audioBase64.trim().length === 0) {
        res.status(400).json({ error: "Missing audioBase64" });
        return;
      }
      if (typeof mimeType !== "string" || mimeType.trim().length === 0) {
        res.status(400).json({ error: "Missing mimeType" });
        return;
      }

      const elevenKey = ELEVENLABS_KEY.value();
      if (!elevenKey) {
        res.status(500).json({ error: "Server not configured (missing ELEVENLABS_KEY)" });
        return;
      }

      const audioBuffer = Buffer.from(audioBase64, "base64");
      console.log("parentVoiceCreate audio bytes", audioBuffer.length);
      if (audioBuffer.length < 200) {
        res.status(400).json({ error: "Audio too short" });
        return;
      }
      if (audioBuffer.length > 12 * 1024 * 1024) {
        res.status(413).json({ error: "Audio too large (max 12MB)" });
        return;
      }

      const form = new FormData();
      form.append("name", typeof name === "string" && name.trim().length > 0 ? name.trim() : "Parent Voice");
      form.append("files", audioBuffer, {
        filename: "parent_sample.m4a",
        contentType: mimeType.trim(),
      });

      const resp = await fetch("https://api.elevenlabs.io/v1/voices/add", {
        method: "POST",
        headers: {
          "xi-api-key": elevenKey,
          ...form.getHeaders(),
        },
        body: form as any,
      });

      if (!resp.ok) {
        const detail = await resp.text();
        console.error("parentVoiceCreate ElevenLabs error", resp.status, detail);
        res.status(502).json({ error: "ElevenLabs voice create failed", detail });
        return;
      }

      const data = (await resp.json()) as { voice_id?: string };
      console.log("parentVoiceCreate ElevenLabs response", data);
      const voiceId = typeof data.voice_id === "string" ? data.voice_id.trim() : "";
      if (!voiceId) {
        res.status(502).json({ error: "Invalid response from ElevenLabs" });
        return;
      }

      await admin.firestore().doc(`users/${uid}/settings/audio`).set(
        {
          elevenVoiceId: voiceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log("parentVoiceCreate saved voiceId", voiceId);

      res.json({ voiceId });
    } catch (e: any) {
      const status = typeof e?.status === "number" ? e.status : 500;
      console.error("Error in parentVoiceCreate:", e);
      res.status(status).json({ error: e?.message || "Server error" });
    }
  }
);
