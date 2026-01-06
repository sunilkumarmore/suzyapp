import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https'; // Use v2 for better performance
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

initializeApp();

const ELEVEN_API_KEY = process.env.ELEVENLABS_KEY || '';

async function verifyFirebaseAuth(req: any) {
  const authHeader = req.headers.authorization || "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) throw new Error("Missing bearer token");

  const idToken = match[1];
  const decoded = await getAuth().verifyIdToken(idToken);
  return decoded.uid;
}

export const parentVoiceSpeak = onRequest({ 
    cors: true, 
    timeoutSeconds: 300 
}, async (req, res) => {
    // 1. BLuntly handle the pre-flight request
    if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'POST');
        res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        res.set('Access-Control-Max-Age', '3600');
        res.status(204).send('');
        return;
    }

    try {
        // 2. Authenticate User
        const uid = await verifyFirebaseAuth(req);

        // 3. Validate Body
        const { storyId, pageIndex, lang, text, voiceId } = req.body ?? {};
        if (!storyId || pageIndex === undefined || !lang || !text || !voiceId) {
            res.status(400).json({ error: 'Missing fields' });
            return;
        }

        // 4. Check Cache
        const cacheKey = `${voiceId}_${storyId}_${pageIndex}_${lang}`;
        const cacheDocRef = admin.firestore().doc(`users/${uid}/voice_cache/${cacheKey}`);
        const cacheDoc = await cacheDocRef.get();
        
        if (cacheDoc.exists) {
            res.json({ audioUrl: cacheDoc.data()!.audioUrl, cached: true });
            return;
        }

        // 5. Call ElevenLabs
        const ttsResp = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
            method: 'POST',
            headers: {
                'xi-api-key': ELEVEN_API_KEY,
                'Content-Type': 'application/json',
                'Accept': 'audio/mpeg',
            },
            body: JSON.stringify({
                text,
                model_id: 'eleven_multilingual_v2',
                voice_settings: { stability: 0.4, similarity_boost: 0.75 },
            }),
        });

        if (!ttsResp.ok) {
            const detail = await ttsResp.text();
            res.status(500).json({ error: 'ElevenLabs TTS failed', detail });
            return;
        }

        // 6. Save to Storage
        const audioBuffer = Buffer.from(await ttsResp.arrayBuffer());
        const bucket = admin.storage().bucket();
        const storagePath = `users/${uid}/voice_cache/${voiceId}/${storyId}/page_${pageIndex}_${lang}.mp3`;
        const file = bucket.file(storagePath);

        await file.save(audioBuffer, { contentType: 'audio/mpeg' });

        // 7. Generate Signed URL (30 days)
        const [signedUrl] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 1000 * 60 * 60 * 24 * 30,
        });

        // 8. Update Firestore Cache
        await cacheDocRef.set({
            storyId, pageIndex, lang, voiceId,
            audioUrl: signedUrl,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        res.json({ audioUrl: signedUrl, cached: false });

    } catch (e: any) {
        console.error("Error in parentVoiceSpeak:", e);
        res.status(401).json({ error: e.message || 'Unauthorized' });
    }
});