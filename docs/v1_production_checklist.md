# V1 Production Release Checklist

Release date: __________  
Release owner: __________  
Go/No-Go approver: __________

Status legend: `[ ]` not done, `[x]` done, `[n/a]` not applicable

## 1) Content Validation Pass

- [ ] **Owner:** Content  
  Validate `assets/coloring/coloring_pages.json` entries (ids unique, required fields present).
- [ ] **Owner:** Content  
  Run preflight script:  
  `python tools/preflight_content_check.py --check-urls`
- [ ] **Owner:** Content  
  Confirm no 0-byte media files in `assets/audio/sfx` and active coloring assets.
- [ ] **Owner:** QA  
  Sample-check at least 5 coloring pages in app for fill correctness and no out-of-bounds leaks.

## 2) Rules Deploy (Firestore + Storage)

- [ ] **Owner:** Backend  
  Review `firestore.rules` + `storage.rules` diff.
- [ ] **Owner:** Backend  
  Deploy rules:  
  `firebase deploy --only firestore:rules,storage`
- [ ] **Owner:** Backend  
  Verify from client:
  - global reads work: `stories`, `adventure_templates`, `coloring_pages`
  - user-private reads/writes work under `users/{uid}/...`
  - unauthorized cross-user access denied.

## 3) Functions Deploy

- [ ] **Owner:** Backend  
  Build functions (if not auto in deploy):  
  `npm --prefix functions run build`
- [ ] **Owner:** Backend  
  Deploy functions:  
  `firebase deploy --only functions`
- [ ] **Owner:** Backend  
  Verify endpoints:
  - `generateNarration`
  - `generateNarrationGlobal`
  - `getSignedAudioUrl`
- [ ] **Owner:** Backend  
  Confirm narration config doc exists: `config/narration.defaultNarratorVoiceId`.

## 4) Smoke Tests (Web + iOS)

### Web Smoke
- [ ] **Owner:** QA  
  Home loads without render overflow.
- [ ] **Owner:** QA  
  Story reading: narrator playback works (including first-time generation wait path).
- [ ] **Owner:** QA  
  Coloring page loads from Firestore URL and fill works.
- [ ] **Owner:** QA  
  Parent voice settings page/tour modal works on small viewport.

### iOS Smoke
- [ ] **Owner:** QA  
  App boots, auth path succeeds, no stuck spinner.
- [ ] **Owner:** QA  
  Story read-aloud works (URL/audio asset/TTS fallback behavior).
- [ ] **Owner:** QA  
  Coloring fill interaction works and SFX plays.
- [ ] **Owner:** QA  
  Parent gate and parent summary flows work.

## 5) Rollback Path (Pre-approved)

- [ ] **Owner:** Backend  
  Record current production deploy references:
  - functions release/tag: __________
  - rules version/tag: __________
  - app build number: __________
- [ ] **Owner:** Backend  
  Keep previous known-good `functions/lib` artifact and rules in git tag: `release-v1-prev`.
- [ ] **Owner:** Release  
  Rollback command plan documented and tested in staging:
  - Functions rollback: deploy previous tagged commit.
  - Rules rollback: deploy previous `firestore.rules` + `storage.rules`.
  - Client rollback: ship previous app build (iOS) / previous hosting build (web).

## Final Go/No-Go

- [ ] All critical checks passed
- [ ] No open Sev-1/Sev-2 issues
- [ ] Approval recorded by Go/No-Go approver

Approver name/signoff: ____________________  
Timestamp: ____________________
