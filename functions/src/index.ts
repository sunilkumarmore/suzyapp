import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getAuth } from "firebase-admin/auth";
import { ElevenLabsClient } from "elevenlabs";
import crypto from "crypto";
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

function sha256Hex(s: string): string {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex");
}

function normalizeTextForHash(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .replace(/\u00A0/g, " ");
}

function safeId(s: string): string {
  return s.trim().replace(/[^a-zA-Z0-9_\-]/g, "_");
}

async function getNarrationConfig(): Promise<{ defaultNarratorVoiceId?: string }> {
  const snap = await admin.firestore().doc("config/narration").get();
  if (!snap.exists) return {};
  const data = snap.data() || {};
  return {
    defaultNarratorVoiceId:
      typeof data.defaultNarratorVoiceId === "string" ? data.defaultNarratorVoiceId.trim() : undefined,
  };
}

function normalizeAudioMimeType(raw: any): string | null {
  if (typeof raw !== "string") return null;
  const base = raw.trim().toLowerCase().split(";")[0]?.trim();
  if (!base) return null;
  return base;
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

      const config = await getNarrationConfig();
      const resolvedVoiceId =
        (typeof voiceId === "string" && voiceId.trim().length >= 3 ? voiceId.trim() : "") ||
        (config.defaultNarratorVoiceId ?? "");
      if (!resolvedVoiceId || resolvedVoiceId.length < 3) {
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
        const entry = pages[String(pageIdxNum)];
        const existingPath = entry?.storagePath;
        const existingUrl = entry?.audioUrl;
        if (typeof existingPath === "string" && existingPath.length > 0) {
          const [signedUrl] = await admin.storage().bucket().file(existingPath).getSignedUrl({
            action: "read",
            expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
          });
          res.json({ audioUrl: signedUrl, cached: true });
          return;
        }
        if (typeof existingUrl === "string" && existingUrl.length > 0) {
          res.json({ audioUrl: existingUrl, cached: true });
          return;
        }
      }

      const ttsResp = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${resolvedVoiceId.trim()}`,
        {
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
        }
      );

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

      const pageKeyStorage = `pages.${pageIdxNum}.storagePath`;
      const pageKeyUrl = `pages.${pageIdxNum}.audioUrl`;
      await personalizedDoc.set(
        {
          storyId: storyId.trim(),
          lang: normLang,
          voiceId: resolvedVoiceId.trim(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          [pageKeyStorage]: storagePath,
          [pageKeyUrl]: admin.firestore.FieldValue.delete(),
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

export const generateNarrationGlobal = onRequest(
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
      await rateLimit(uid, "generateNarrationGlobal", 60 * 1000, 15);

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

      const config = await getNarrationConfig();
      const resolvedVoiceId =
        (typeof voiceId === "string" && voiceId.trim().length >= 3 ? voiceId.trim() : "") ||
        (config.defaultNarratorVoiceId ?? "");
      if (!resolvedVoiceId || resolvedVoiceId.length < 3) {
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

      const stability = typeof body.stability === "number" ? body.stability : 0.4;
      const similarity_boost =
        typeof body.similarity_boost === "number" ? body.similarity_boost : 0.75;
      const style = typeof body.style === "number" ? body.style : undefined;
      const use_speaker_boost =
        typeof body.use_speaker_boost === "boolean" ? body.use_speaker_boost : undefined;
      const speed = typeof body.speed === "number" ? body.speed : undefined;

      const voiceSettings: Record<string, any> = {
        stability,
        similarity_boost,
      };
      if (typeof style === "number") voiceSettings.style = style;
      if (typeof use_speaker_boost === "boolean") voiceSettings.use_speaker_boost = use_speaker_boost;
      if (typeof speed === "number") voiceSettings.speed = speed;

      const elevenKey = ELEVENLABS_KEY.value();
      if (!elevenKey) {
        res.status(500).json({ error: "Server not configured (missing ELEVENLABS_KEY)" });
        return;
      }

      const storySafe = safeId(storyId);
      const voiceSafe = safeId(resolvedVoiceId);
      const normalizedForHash = normalizeTextForHash(cleanText);
      const textHash = sha256Hex(normalizedForHash);
      const cacheKey = sha256Hex(`v1|${voiceSafe}|${storySafe}|${pageIdxNum}|${normLang}|${textHash}`);

      const cacheDocRef = admin.firestore().doc(`narrationCache/${cacheKey}`);
      const storagePath =
        `narration_cache/${voiceSafe}/${storySafe}/page_${pageIdxNum}_${normLang}_${textHash}.mp3`;
      const bucket = admin.storage().bucket();
      const file = bucket.file(storagePath);

      const now = Date.now();
      const lockExpiresAt = now + 3 * 60 * 1000;

      const actionRef: { value: "RETURN_READY" | "WAIT" | "GENERATE" } = { value: "WAIT" };
      let existingStoragePath: string | null = null;

      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(cacheDocRef);

        if (snap.exists) {
          const data = snap.data() || {};
          const status = data.status as string | undefined;
          const sp = typeof data.storagePath === "string" ? data.storagePath : null;
          const generatingUntil = typeof data.generatingUntil === "number" ? data.generatingUntil : 0;

          if (status === "READY" && sp) {
            actionRef.value = "RETURN_READY";
            existingStoragePath = sp;
            return;
          }

          if (status === "GENERATING" && generatingUntil > now) {
            actionRef.value = "WAIT";
            existingStoragePath = sp;
            return;
          }

          tx.set(
            cacheDocRef,
            {
              status: "GENERATING",
              generatingUntil: lockExpiresAt,
              storagePath,
              storyId: storySafe,
              pageIndex: pageIdxNum,
              lang: normLang,
              voiceId: voiceSafe,
              textHash,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              error: admin.firestore.FieldValue.delete(),
            },
            { merge: true }
          );
          actionRef.value = "GENERATE";
          existingStoragePath = storagePath;
          return;
        }

        tx.create(cacheDocRef, {
          status: "GENERATING",
          generatingUntil: lockExpiresAt,
          storagePath,
          storyId: storySafe,
          pageIndex: pageIdxNum,
          lang: normLang,
          voiceId: voiceSafe,
          textHash,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        actionRef.value = "GENERATE";
        existingStoragePath = storagePath;
      });

      if (actionRef.value === "RETURN_READY") {
        const [signedUrl] = await bucket.file(existingStoragePath!).getSignedUrl({
          action: "read",
          expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
        });
        res.json({ status: "READY", audioUrl: signedUrl, cached: true });
        return;
      }

      if (actionRef.value === "WAIT") {
        res.status(202).json({ status: "GENERATING", retryAfterMs: 1500 });
        return;
      }

      const ttsResp = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${resolvedVoiceId.trim()}`,
        {
        method: "POST",
        headers: {
          "xi-api-key": elevenKey,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
        body: JSON.stringify({
          text: cleanText,
          model_id: "eleven_multilingual_v2",
          voice_settings: voiceSettings,
        }),
        }
      );

      if (!ttsResp.ok) {
        const detail = await ttsResp.text();
        await cacheDocRef.set(
          {
            status: "FAILED",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            error: `ElevenLabs TTS failed: ${detail?.slice(0, 500)}`,
            generatingUntil: admin.firestore.FieldValue.delete(),
          },
          { merge: true }
        );
        res.status(502).json({ error: "ElevenLabs TTS failed", detail });
        return;
      }

      const audioBuffer = Buffer.from(await ttsResp.arrayBuffer());
      if (audioBuffer.length < 200) {
        await cacheDocRef.set(
          {
            status: "FAILED",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            error: "Invalid audio returned from ElevenLabs",
            generatingUntil: admin.firestore.FieldValue.delete(),
          },
          { merge: true }
        );
        res.status(502).json({ error: "Invalid audio returned from ElevenLabs" });
        return;
      }

      await file.save(audioBuffer, { contentType: "audio/mpeg" });

      await cacheDocRef.set(
        {
          status: "READY",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          generatingUntil: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );

      const [signedUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
      });

      res.json({ status: "READY", audioUrl: signedUrl, cached: false });
    } catch (e: any) {
      const status = typeof e?.status === "number" ? e.status : 500;
      console.error("Error in generateNarrationGlobal:", e);
      res.status(status).json({ error: e?.message || "Server error" });
    }
  }
);

export const getSignedAudioUrl = onRequest(
  {
    cors: true,
    timeoutSeconds: 60,
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
      await rateLimit(uid, "getSignedAudioUrl", 60 * 1000, 60);

      const body = req.body ?? {};
      const storagePathRaw = body.storagePath;
      if (typeof storagePathRaw !== "string" || storagePathRaw.trim().length === 0) {
        res.status(400).json({ error: "Missing storagePath" });
        return;
      }

      const storagePath = storagePathRaw.trim();
      const userPrefix = `users/${uid}/personalized_audio/`;
      const globalPrefix = "narration_cache/";
      if (!storagePath.startsWith(userPrefix) && !storagePath.startsWith(globalPrefix)) {
        res.status(403).json({ error: "Invalid storagePath" });
        return;
      }

      const [signedUrl] = await admin.storage().bucket().file(storagePath).getSignedUrl({
        action: "read",
        expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
      });

      res.json({ audioUrl: signedUrl });
    } catch (e: any) {
      const status = typeof e?.status === "number" ? e.status : 500;
      console.error("Error in getSignedAudioUrl:", e);
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
      const elevenKey = ELEVENLABS_KEY.value();
      if (!elevenKey) {
        res.status(500).json({ error: "Server not configured (missing ELEVENLABS_KEY)" });
        return;
      }

      const base64Payload = audioBase64.includes(",")
        ? audioBase64.split(",").pop() || ""
        : audioBase64;
      const audioBuffer = Buffer.from(base64Payload, "base64");
      console.log("parentVoiceCreate audio bytes", audioBuffer.length);
      if (audioBuffer.length < 200) {
        res.status(400).json({ error: "Audio too short" });
        return;
      }
      if (audioBuffer.length > 12 * 1024 * 1024) {
        res.status(413).json({ error: "Audio too large (max 12MB)" });
        return;
      }

      const normalizedMimeType = normalizeAudioMimeType(mimeType) || "audio/mpeg";
      const ext = normalizedMimeType.includes("/") ? normalizedMimeType.split("/")[1] : "bin";
      const file = new File([audioBuffer], `sample.${ext}`, { type: normalizedMimeType });
      const client = new ElevenLabsClient({ apiKey: elevenKey });
      const voice = await client.voices.add({
        name: typeof name === "string" && name.trim().length > 0 ? name.trim() : "Parent Voice",
        files: [file],
        remove_background_noise: true,
      });
      const voiceId = typeof voice.voice_id === "string" ? voice.voice_id.trim() : "";
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
