# Quex: a local-first AI study companion for kids

Quex helps a child study from the exact worksheet, textbook page, or notes they already have. It turns a photo into a quiz, explains mistakes in plain language, and keeps working offline on-device with Gemma 4. The goal is simple: make homework help available even when a parent is busy, the internet is unreliable, or the child only has one device.

## Problem

In many homes, the hardest part of studying is not the content itself. It is getting timely help when a child gets stuck.

Quex focuses on that gap:

- Parents are often unavailable during study time.
- A child may not have a teacher, tutor, or older sibling nearby.
- School materials are usually on paper, not in a clean digital format.
- Cloud-based tutoring is fragile when connectivity is poor or expensive.

That is why Quex is built as a quiet, offline-first tutor rather than a general chatbot.

### Why this matters

Two context numbers explain why Quex is worth building:

- 28% of Indonesian students can't find anyone to help them with schoolwork at home. Source: PISA 2022, OECD.
- 53.8% of Indonesian parents couldn't accompany their children's study time because of work. Source note: BSKAP / The Conversation Indonesia.

Those numbers are not just a video hook. They describe the gap Quex is meant to close: the child has the material, but not always the help.

## Why Quex exists

The app grew from a very ordinary household moment: a child has a test coming up, the parent is busy, and the study material is already in front of them. Quex is meant to reduce that friction.

Instead of asking a child to type out a question, copy a worksheet into a chatbot, or wait for a network connection, Quex lets them:

1. open a study session,
2. photograph the page,
3. get a quiz from that material,
4. answer,
5. receive a simple explanation when they are wrong,
6. retry until the concept clicks.

That is the whole product loop.

## Demo flow

The demo follows one tight story:

1. A child opens Quex and chooses a profile.
2. They create or open a study session for a subject or chapter.
3. They take a photo of the worksheet or textbook page.
4. Quex generates quiz questions from the material.
5. The child answers a question.
6. If the answer is wrong, Quex explains the concept again.
7. The child retries with better understanding.

This is the sequence the video should show, and it is the sequence judges should remember.

## How it works

Quex is a Flutter app built around on-device inference and local persistence.

### AI layer

- Gemma 4 E4B or E2B runs locally in LiteRT-LM format.
- `flutter_gemma` provides the on-device chat and generation flow.
- The app selects a model variant based on available device memory.
- Quiz generation and tutoring use persistent sessions instead of one-shot prompts.

### Storage layer

- Study sessions, materials, quizzes, questions, and chat history are stored in SQLite.
- Lightweight app state such as active profile and model readiness lives in SharedPreferences.
- The app keeps the study history on-device so the experience survives weak or missing connectivity.

### Product layer

- The camera flow turns real paper pages into study material.
- The quiz flow turns that material into practice.
- The tutor flow explains mistakes in simple language.
- The voice input modal makes the interaction feel fast and natural.

## Proof points

The writeup should include concrete evidence here before submission.

### Screenshots to add

- [ ] Profile selection screen
- [ ] Camera capture or material upload
- [ ] Quiz generation screen
- [ ] Wrong-answer explanation screen
- [ ] Tutor chat or voice input modal
- [ ] Offline mode / airplane mode proof

### Metrics to add

- [ ] Device tested
- [ ] Model variant used
- [ ] First quiz generation time
- [ ] First response latency
- [ ] App start or model load time
- [ ] Offline behavior notes

### Two video metrics to show

These are the two numbers that should appear in the demo video or caption overlays:

- Capture to quiz ready: `__ s` from photo capture to the first quiz screen.
- Help to explanation ready: `__ s` from tapping help to the explanation starting.

### Current verified proof from the repo

- Quex runs on-device with Gemma 4 E4B or E2B in LiteRT-LM format.
- The app stores study data locally with SQLite.
- The core tutoring flow is designed around persistent sessions.
- The product is meant to remain useful without a cloud API.

## What works well today

The strongest parts of the current build are:

- Voice input modal is responsive and easy to use.
- Multilanguage behavior is solid for the intended tutoring flow.
- Vision is good enough for photographed worksheets and textbook pages.
- Offline-first behavior is credible and central to the product.
- The same local model can support quiz generation and explanation.

## Brief Gemma 4 feedback

Quex is a good fit for Gemma 4, but the integration also surfaced a few gaps that are worth calling out honestly:

- LiteRT-LM currently does not expose a visual token budget setting, which makes dense page handling harder to tune.
- `flutter_gemma` still needs a better multi-image upload path, and this project already contributed to [DenisovAV/flutter_gemma#262](https://github.com/DenisovAV/flutter_gemma/pull/262).
- Gemma 4 steering in thinking mode is still hard for this tutoring use case.
- Tool calling becomes unreliable in long-context sessions and can corrupt the output stream.

These are not blockers for Quex, but they are the main rough edges that affect reliability in a real study flow.

## Why Gemma 4 still fits

Gemma 4 still fits Quex well because the product depends more on practical interaction quality than benchmark theater.

- The vision experience is good for real study material.
- Voice and multilingual support make the app usable for children.
- On-device inference matters more than cloud convenience in this use case.
- The app is strongest when it can go from photo to quiz to explanation without leaving the device.

## Closing summary

Quex is not trying to be a broad AI tutor for everyone. It is a focused offline study companion for kids who need help with the exact page in front of them.

The submission should make three things obvious:

1. the problem is real,
2. the product works on-device,
3. Gemma 4 is a credible fit for the workflow.

That is the story the video should support, and the story the judges should be able to scan quickly in this writeup.
