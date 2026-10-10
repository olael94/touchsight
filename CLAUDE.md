# Fingertip Guide (working title)

> Project brief for Claude Code. Read this entire file before writing any code.
> Built solo by Oliver Rivera at Ensign BUILD 2026 (Ensign College, Oct 9 to 10, 2026).
> Hard deadline: **Saturday Oct 10, 12:00 PM** (all code submitted, repo public).

---

## 0. Instructions for Claude Code

- **Build in milestone order (Section 9).** After every milestone, the app must still build and run on the iPhone. A working demo at all times beats an ambitious broken one.
- **Oliver is new to Swift.** He knows React, React Native/Expo, Next.js, Spring Boot, FastAPI. When you introduce a Swift, ARKit, or Vision concept, explain it in one or two plain sentences. "Learning" is 25% of the judging score, so his understanding matters.
- **Keep files small and focused.** One responsibility per file (see Section 6).
- **Never hardcode API keys.** The repo must be public (hackathon rule). Use a gitignored `Secrets.xcconfig` or `Secrets.swift` (see Section 7.8).
- **Ask before large refactors** or swapping a core technology.
- **No em dashes** in any docs, README, or comments you write. Use commas, colons, or periods.
- **Avoid generic boilerplate.** Prefer clear, specific names (`FingertipTracker`, `PanelAnchorStore`) over `Manager`, `Helper`, `Utils`.
- When something is uncertain (an API detail, coordinate convention), say so and propose a quick test rather than guessing.

---

## 1. Concept (one sentence)

**Fingertip Guide helps blind and low-vision people press the right buttons on flat, non-tactile panels (elevators, microwaves, appliances) by tracking their fingertip with the iPhone camera and LiDAR and guiding it to the exact button by voice, sound, and haptics.**

### The problem
A white cane or guide app can get a blind person *to* the elevator or the microwave. But once they are there, many panels are flat: membrane buttons, touch panels, no braille, no tactile bumps. They cannot tell where "3" or "Start" is. Existing apps (Seeing AI, Be My Eyes, Apple Magnifier) **describe** what is in front of you, and navigation apps guide your **feet**. Almost nothing guides your **finger** to a specific target in real time.

### The solution
The user wears or holds the iPhone at chest height (like a body camera), says what they want ("Microwave, two minutes" or "Third floor"), and points. The app:
1. Finds and **locks onto** the panel in 3D space.
2. Turns the spoken goal into a **sequence of buttons** using AI.
3. Tracks the user's fingertip and guides it, in real time, to each button: "Right... up... forward... press."
4. Detects each press and moves to the next button until the goal is done.

---

## 2. User flow (end to end)

1. **Launch:** user presses the iPhone **Action button** (or says "Hey Siri, start Fingertip Guide"). An App Intent opens the app and starts a session immediately. No screen tapping required.
2. **Position:** phone is held against the chest (or in a chest strap/lanyard), back camera facing forward.
3. **Goal by voice:** app speaks "What do you want to do?" User says "Microwave, two minutes" or "Floor three." (Tap fallback: big on-screen preset buttons for the demo.)
4. **Find the panel:** user slowly turns their body. The app scans for a button panel. Audio beeps speed up and get louder as the panel moves toward the center of view (metal detector style).
5. **Lock:** when a panel is detected, the app anchors it in 3D (ARKit) and speaks: "Panel found, slightly to your right, about one meter away."
6. **Approach:** if the panel is far (more than ~60 cm), the app guides the user closer: "Step forward... slightly right... stop."
7. **Rescan up close:** at arm's length, the app runs a high-accuracy scan to read every button label and anchors each button in 3D.
8. **Plan:** the spoken goal + the list of detected buttons go to an LLM, which returns an ordered button sequence (e.g., `["2", "0", "0", "Start"]`). The app confirms out loud: "I will guide you to press 2, 0, 0, then Start."
9. **Guide the finger:** user points with their index finger. The app tracks the fingertip in 3D and gives directional guidance relative to the panel: left/right, up/down, forward/back. Beeps get faster as the finger gets closer.
10. **Press detection:** when the fingertip is on the target and touching the panel surface (LiDAR depth) and holds briefly, the app says "Press" and then "Pressed" once detected, and moves to the next button.
11. **Done:** "Microwave set for two minutes." Session ends or waits for a new goal.

**Lost states:**
- Panel leaves view: "Panel lost, turn slightly left" (based on last known anchor direction).
- Hand leaves view: "I can't see your hand, point toward the panel."
- Low confidence: "Hold still, rescanning."

---

## 3. Platform decision

**Native iOS app, Swift + SwiftUI + ARKit + Vision.** Not Expo, not web.

Why:
- **LiDAR and ARKit are native only.** Safari gives no depth access.
- **ARKit world tracking** keeps button positions locked in 3D while the phone moves on the user's chest. This solves "the camera moves" for free.
- **Apple Vision framework** provides hand pose (fingertip) and text recognition (OCR) on-device, fast, no extra libraries. No MediaPipe needed.
- Pure SwiftUI avoids the React Native bridge, which would make per-frame camera processing much harder tonight.
- Haptics (Core Haptics), on-device speech recognition, and App Intents (Action button) are all first-party.

Target: **iPhone 16 Pro Max** (has LiDAR), **iOS 17+**, portrait orientation only.

---

## 4. Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| UI | SwiftUI | Minimal accessible UI + debug overlay |
| AR session | ARKit (`ARWorldTrackingConfiguration`, `frameSemantics = .sceneDepth`) | Camera frames, world tracking, LiDAR depth |
| Plane detection | ARKit `planeDetection = [.vertical]` + raycasting | Find the panel surface |
| Fingertip | Vision `VNDetectHumanHandPoseRequest` (`.indexTip`) | 2D fingertip position each frame |
| Button text | Vision `VNRecognizeTextRequest` (`.fast` while searching, `.accurate` when locked) | Button labels + positions |
| Panel shape (optional) | Vision `VNDetectRectanglesRequest` | Help detect the panel boundary |
| Icon buttons (optional) | Cloud vision model (Gemini or Claude) | Label buttons with icons only (power, arrows, door open/close) |
| Goal planning | LLM API (Claude, Gemini, or OpenAI, whichever key is available) | Spoken goal + button list to ordered button sequence (JSON) |
| Speech in | `SFSpeechRecognizer` (on-device, en-US and es-MX) | Capture the user's goal |
| Speech out | `AVSpeechSynthesizer` | Directions and confirmations |
| Audio cues | `AVAudioEngine` (+ `AVAudioEnvironmentNode` for spatial audio, stretch) | Proximity beeps |
| Haptics | Core Haptics / `UIImpactFeedbackGenerator` | Proximity pulses, felt against the chest |
| Launch | App Intents (`AppIntent`, `AppShortcutsProvider`) | Action button + Siri launch |
| Networking | `URLSession` + `Codable` | LLM calls |

No third-party dependencies required for the core. Avoid adding packages unless clearly necessary.

---

## 5. How it works technically

### 5.1 AR session
- `ARSession` with `ARWorldTrackingConfiguration`.
- Enable `frameSemantics.insert(.sceneDepth)` if `ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)`.
- Enable vertical plane detection (panels are on walls or appliance fronts).
- Use `ARSCNView` or `ARView` (RealityKit) as the camera preview. Either is fine; pick the simpler one for drawing a 2D debug overlay on top.
- Receive frames via `ARSessionDelegate.session(_:didUpdate:)`. **Do not** run heavy Vision work on every frame on the main thread. Use a serial background queue and drop frames if busy.

### 5.2 Fingertip tracking (every frame, ~30 FPS target)
1. Run `VNDetectHumanHandPoseRequest` on `frame.capturedImage` with `maximumHandCount = 1`.
2. Read `.indexTip` (and `.indexDIP` for direction). Ignore points with confidence below ~0.5.
3. Convert Vision's normalized point to image pixel coordinates (see 5.8 on coordinate conventions).
4. **3D fingertip:** sample LiDAR `sceneDepth.depthMap` at the fingertip pixel. The depth map is low resolution (~256x192), so scale coordinates. Sample a small window (e.g., 5x5) and take the **minimum valid depth** so a thin finger is not missed in favor of the wall behind it. Check `confidenceMap` if available.
5. Unproject (pixel + depth + camera intrinsics + camera transform) into a **world-space 3D point**.
6. Smooth with a simple exponential moving average to reduce jitter.

### 5.3 Panel detection and lock
- **Searching mode:** every ~0.4 s, run `VNRecognizeTextRequest` (`.fast`) on the frame. A "panel candidate" is a cluster of short text tokens typical of panels: digits `0-9`, `B`, `L`, `G`, `Start`, `Stop`, `Cancel`, `Open`, `Close`, `Popcorn`, etc. Require at least ~4 tokens close together.
- Optionally confirm with `VNDetectRectanglesRequest` around the cluster.
- Compute the cluster's center in the image. Use this for the "metal detector" audio cue (distance from image center drives beep rate and stereo pan).
- **Lock:** raycast from the cluster center (`ARRaycastQuery`, target `.estimatedPlane` or `.existingPlaneGeometry`, alignment `.vertical`), or use LiDAR depth at that pixel. Place an `ARAnchor` named `panel` at the hit point. Store the panel plane's **normal** and an **up vector** (world gravity up, ARKit world Y axis).

### 5.4 Approach
- Distance = distance from the camera position to the panel anchor (meters, from LiDAR/ARKit).
- Direction = panel anchor position expressed in the camera's coordinate frame (left/right, up/down).
- Speak only when the instruction changes. Thresholds (tune live): far > 1.2 m "keep walking", 0.6 to 1.2 m "slow down", < 0.6 m "stop, raise your hand and point".

### 5.5 Button mapping (rescan up close)
1. When distance < ~0.6 m and the camera is steady, run `VNRecognizeTextRequest` with `.accurate`, `recognitionLanguages = ["en-US", "es-MX"]`, `usesLanguageCorrection = false` (short tokens like "3" get "corrected" otherwise).
2. For each recognized token: take its bounding box center, raycast or depth-unproject to a world point, and create a `PanelButton` with `label`, `worldPosition`, `size estimate`.
3. Merge duplicates (same label within ~2 cm).
4. **Optional icon pass:** send one cropped JPEG of the panel to a cloud vision model asking for icon-only buttons with normalized bounding boxes. Gemini returns boxes as `[ymin, xmin, ymax, xmax]` normalized to 0 to 1000. Map those into the same world anchoring pipeline.
5. Each frame, project every button's world position back to the screen with `ARCamera.projectPoint(_:orientation:viewportSize:)` for the debug overlay. Because buttons live in world space, they stay correct as the phone moves.

**Important:** the panel must be mapped **before** the hand gets close, because the hand will cover labels.

### 5.6 Goal planning (AI)
- Input: the transcribed utterance + the list of detected button labels (and a panel type guess: elevator, microwave, unknown).
- Output: strict JSON with the ordered button labels to press.
- **Local fast path first** (no network): simple rules for common cases, e.g., microwave "N minutes" → digits + `Start`; elevator "floor N" → `N`. Call the LLM only if rules fail or for unusual requests. This keeps the demo working even if the network is bad.

Prompt contract (send as system + user messages):

```
System: You convert a blind user's spoken goal into an ordered list of buttons to press on a physical panel.
Only use labels from AVAILABLE_BUTTONS. If impossible, return an error with a short spoken explanation.
Respond with JSON only.

User:
PANEL_TYPE: microwave
AVAILABLE_BUTTONS: ["1","2","3","4","5","6","7","8","9","0","Start","Stop/Cancel","Popcorn","Defrost","Power","Timer"]
GOAL: "two minutes"
```

Expected response:

```json
{
  "sequence": ["2", "0", "0", "Start"],
  "spoken_summary": "I will guide you to press 2, 0, 0, then Start.",
  "error": null
}
```

Validate the response: every label must exist in the detected buttons. If not, fall back to asking the user to rephrase.

### 5.7 Finger guidance engine (the heart of the app)
For the current target button:
1. `delta = targetWorldPosition - fingertipWorldPosition`.
2. Build a **panel coordinate frame**:
   - `normal` = panel plane normal (pointing out of the panel toward the user)
   - `up` = world up (0, 1, 0), made orthogonal to `normal`
   - `right` = `up × normal` (check sign so "right" matches the user's right when facing the panel)
3. Project: `dx = delta · right`, `dy = delta · up`, `dz = delta · (-normal)` (how far the finger still has to move toward the panel).
4. Decide the instruction with priorities:
   - If `|dx|` or `|dy|` > ~2 cm: say the dominant direction ("left", "right", "up", "down"), optionally with a size word ("a little left").
   - Else if `dz` > ~1.5 cm: "forward" / "press".
   - Else: on target.
5. **Feedback channels:**
   - Speech: only when the instruction changes, max once every ~0.8 s. Short words.
   - Beeps: rate increases as total distance shrinks (parking sensor style). Continuous tone when on target.
   - Haptics: pulse intensity increases with closeness (felt against the chest).
6. Hysteresis: require the new instruction to persist for ~3 frames before speaking, to avoid flip-flopping.

### 5.8 Coordinate conventions (common bug source, be careful)
- Vision normalized coordinates: origin **bottom-left**, range 0 to 1.
- `frame.capturedImage` is in the sensor's **landscape** orientation even when the phone is portrait. Pass the right orientation to Vision (`.right` for portrait with back camera) or convert explicitly.
- `sceneDepth.depthMap` has a different, lower resolution than `capturedImage`; scale coordinates.
- Use `frame.displayTransform(for:viewportSize:)` to convert normalized image coordinates to the on-screen overlay.
- **Write one `CoordinateMapper` file** that owns all of these conversions, with a visual debug test: draw the fingertip dot on screen and confirm it sits on the real fingertip before building anything on top of it.

### 5.9 Press detection
A press is registered when **all** are true:
- Fingertip is within the target's radius in the panel plane (`|dx|, |dy|` < ~1.5 cm).
- Fingertip depth is within ~1 cm of the panel plane (touching).
- Condition holds for ~400 ms (dwell).

Then: speak "Pressed", play a confirmation sound, advance to the next button. Optional confirmation: a manual "next" (tap anywhere on screen or say "done") for robustness during the demo.

### 5.10 State machine
```
idle
 → listeningForGoal
 → searchingPanel
 → panelLocked
 → approaching            (skipped if already close)
 → mappingButtons
 → planningSequence
 → guidingFinger(step i)
 → pressDetected(step i)  → guidingFinger(step i+1) ...
 → completed
Any state → recovering (panelLost / handLost / lowConfidence) → back to previous state
```
Implement as a Swift `enum SessionState` owned by a single `@Observable` / `ObservableObject` `SessionController`. All feedback (speech, beeps, haptics) is driven from state changes, not scattered across files.

---

## 6. Suggested project structure

```
FingertipGuide/
├── App/
│   ├── FingertipGuideApp.swift
│   ├── StartGuidanceIntent.swift        # App Intent for Action button / Siri
│   └── AppShortcuts.swift
├── Session/
│   ├── SessionController.swift          # state machine, orchestrates everything
│   └── SessionState.swift
├── AR/
│   ├── ARSessionRunner.swift            # config, frame delivery, background queue
│   ├── CoordinateMapper.swift           # ALL coordinate conversions live here
│   └── DepthSampler.swift               # LiDAR depth lookup + unprojection
├── Vision/
│   ├── FingertipTracker.swift           # hand pose → smoothed 3D fingertip
│   ├── PanelDetector.swift              # fast OCR clustering → panel candidate
│   └── ButtonMapper.swift               # accurate OCR → PanelButton anchors
├── Guidance/
│   ├── GuidanceEngine.swift             # delta → instruction (dx, dy, dz)
│   ├── PressDetector.swift
│   └── PanelFrame.swift                 # right/up/normal vectors
├── Feedback/
│   ├── Speaker.swift                    # AVSpeechSynthesizer, rate limiting, EN/ES
│   ├── BeepPlayer.swift                 # AVAudioEngine proximity beeps
│   └── HapticPlayer.swift
├── AI/
│   ├── GoalPlanner.swift                # local rules first, then LLM
│   ├── LLMClient.swift                  # URLSession call, JSON decode
│   └── Secrets.swift                    # GITIGNORED
├── Speech/
│   └── GoalListener.swift               # SFSpeechRecognizer
├── UI/
│   ├── ContentView.swift                # big Start button, status text
│   ├── DebugOverlayView.swift           # boxes, fingertip dot, distances
│   └── PresetGoalsView.swift            # tap fallback for demo
└── Models/
    ├── PanelButton.swift
    └── GuidanceInstruction.swift
```

---

## 7. Requirements and setup details

### 7.1 Xcode project
- New iOS App, SwiftUI, Swift, iOS 17.0 minimum, iPhone only, portrait only.
- Sign with Oliver's Apple ID (free personal team is fine for running on his own device).

### 7.2 Info.plist keys
- `NSCameraUsageDescription`: "Fingertip Guide uses the camera to find panels and track your finger."
- `NSMicrophoneUsageDescription`: "Fingertip Guide listens for what you want to do."
- `NSSpeechRecognitionUsageDescription`: "Fingertip Guide turns your voice into a goal."
- Required device capabilities: `arkit`.

### 7.3 Accessibility
- The whole flow must work **without looking at the screen**.
- Every state change is spoken.
- Compatible with VoiceOver: large single "Start" button, clear accessibility labels.
- High-contrast debug overlay is for sighted judges and developers; can be toggled.

### 7.4 Languages
- English first. Spanish (es-MX) for speech in/out as a stretch: same engine, translated phrase table in `Speaker.swift`.

### 7.5 Performance targets
- Hand pose: every frame if possible, minimum ~15 FPS.
- Fast OCR while searching: every ~0.4 s.
- Accurate OCR: once on lock, plus manual rescan.
- Guidance latency (finger moves → feedback): under ~200 ms.

### 7.6 Demo modes
- **Presentation mode:** clean camera view, large status text, subtle overlay.
- **Debug mode:** button boxes with labels, fingertip dot, dx/dy/dz numbers, FPS, state name.

### 7.7 Fallbacks (keep the demo alive)
- 3D anchoring unstable → fall back to 2D image-space guidance with the phone held steady.
- LiDAR depth noisy at fingertip → use dwell in 2D + manual "next" tap for press confirmation.
- OCR misses buttons → cloud vision pass, or a printed demo panel with high-contrast labels.
- Speech recognition fails → preset goal buttons ("Microwave 2 min", "Floor 3").
- Network down → local rule-based goal planner.

### 7.8 Secrets
- `AI/Secrets.swift` (gitignored) contains `enum Secrets { static let llmAPIKey = "..." }`.
- Commit `AI/Secrets.example.swift` with a placeholder.
- Add `Secrets.swift` to `.gitignore` **before the first commit**.

---

## 8. Hackathon context (why decisions were made)

**Judging (equal weight):**
1. **Technology:** ARKit world tracking + LiDAR depth + on-device Vision (hand pose + OCR) + LLM planning + 3D math for guidance.
2. **Design:** voice-first, eyes-free UX; parking-sensor beeps; haptics on the chest; Action button launch.
3. **Completion:** milestone plan guarantees a working demo at every stage.
4. **Learning:** Oliver's first real Swift / ARKit / Vision project, coming from React and Spring Boot.

**Not judged:** code quality, pitch quality, idea originality. **A live demo is strongly encouraged.**

**Rules to respect:**
- All code written during the event (started 8:30 PM Oct 9).
- Repo must be **public** and stay public.
- List all AI tools used (Claude Code, any LLM APIs) in the submission and README.
- Small bug fixes allowed after the deadline, no new features.

**Prior art (be ready to answer "how is this different?"):** Seeing AI, Be My Eyes, Apple Magnifier Detection Mode describe scenes or detect doors. Navigation apps (e.g., Harvard's Mobilio research) guide walking. Fingertip Guide guides the **finger to a specific button** in real time using 3D tracking. The CMU research project VizLens explored panel reading years ago; this is a modern, on-device, LiDAR-based take.

---

## 9. Milestones (build in this order)

Build starts 8:30 PM Friday. Building entry closes at midnight (stay inside or plan accordingly). Deadline 12:00 PM Saturday.

| # | Target time | Milestone | Done when |
|---|---|---|---|
| M0 | 10:30 PM | Project runs on iPhone, AR camera view, debug overlay shell | Camera preview on phone, FPS shown |
| M1 | 12:30 AM | Fingertip tracking + coordinate mapping verified | Dot sits on the real fingertip while moving |
| M2 | 2:00 AM | OCR button mapping + 3D anchoring | Button boxes stay on the real buttons when the phone moves |
| M3 | 4:00 AM | Guidance engine for ONE hard-coded target, with speech + beeps + dz via LiDAR | Eyes closed, Oliver reaches the target button |
| M4 | 6:00 AM | Press detection + multi-step sequence + local goal rules | "2, 0, 0, Start" completes end to end |
| M5 | 8:00 AM | Voice goal (SFSpeechRecognizer) + LLM planner + App Intent / Action button | Action button → speak goal → guided presses |
| M6 | 9:30 AM | Find + lock + approach phase with metal detector beeps | Works starting from ~2 m away |
| M7 | 11:30 AM | Polish, Spanish mode (stretch), README, demo rehearsal, record backup video | Ready to demo |
| | 12:00 PM | **Submit, repo public** | |

If a milestone runs more than ~45 minutes late, cut scope from the later milestones, not quality from the earlier ones.

---

## 10. Demo script (for judging, 1:00 to 2:30 PM)

1. Show the problem: a flat microwave or elevator-style panel (have a printed backup panel).
2. Put on a blindfold. Phone on chest strap.
3. Press the Action button. Say "Microwave, two minutes."
4. App finds and locks the panel, guides the finger: 2, 0, 0, Start. Each press confirmed.
5. Remove blindfold, switch to debug mode, show the 3D boxes, fingertip tracking, and dx/dy/dz values.
6. Invite a judge to try it blindfolded.
7. Close with what was learned (first Swift/ARKit app) and next steps (spatial audio, more panel types, Apple Watch haptics, braille-free public spaces).

---

## 11. Name candidates (undecided)
- **Fingertip Guide** (clear, descriptive)
- **Touchpoint** (short, product-like)
- **Guía** (Spanish for "guide," fits the bilingual angle)
- **PressPoint**

---

## 12. Known risks
- OCR on shiny metal elevator buttons with engraved labels may be poor. Test early; prefer high-contrast panels for the demo.
- The hand covers labels when close, so mapping must happen before reaching.
- LiDAR depth at a thin fingertip can be noisy; use the min-depth window + smoothing.
- Speech output can overlap and become noise; rate-limit aggressively.
- Fatigue: keep commits small and frequent so nothing is lost at 4 AM.
