# TouchSight

**A white cane gets you to the microwave. TouchSight gets your finger to the button.**

TouchSight is an iOS app that helps blind and low-vision people press the right buttons on flat, non-tactile panels: microwaves, appliances, and elevators. It tracks the user's fingertip with the iPhone camera and LiDAR, and guides it to the exact button by voice, beeps, and haptics felt against the chest.

Built solo by **Oliver Rivera** at **Ensign BUILD 2026** (Ensign College, Salt Lake City, October 9 to 10, 2026).

---

## Inspiration

There are great apps that help blind people get around: they guide them along streets and warn them about obstacles. But once they arrive at an elevator or a kitchen, there is no app, at least that I know of, that helps them find the button panel and press the right button on their own. Many panels are flat, with no braille and no bumps, so calling an elevator or setting a microwave still means asking someone for help.

TouchSight guides your finger, not just your feet. Elevators and microwaves are only the start: the same idea works for ATMs, thermostats, washing machines, and kiosks.

This was my first time using Xcode and Swift, so it was a real challenge. With Claude as my mentor, I built this working MVP overnight.

## The problem

Many modern panels are flat: membrane buttons, touch panels, no braille, no bumps. A cane or a navigation app can get a blind person *to* the elevator or the microwave, but not to the "3" or the "Start" button.

Existing apps like Seeing AI, Be My Eyes, and Apple Magnifier **describe** what is in front of you. Navigation apps guide your **feet**. TouchSight guides your **finger**, in real time, to a specific button.

## What it does

1. **Press the Action button** (or run the shortcut with Siri). TouchSight asks: *"What do you want to do?"*
2. **Say the goal:** "Microwave, two minutes", "Heat my food for a minute and a half", or "I'm on floor 1, take me to floor 5".
3. **Find the panel:** if no panel is scanned yet, the app looks for one and guides you toward it ("Panel found, about 1.5 meters, to your left. Turn left... Step forward... Stop").
4. **Read the panel:** Claude vision finds every button, including arrow icons and unlabeled elevator call buttons, and LiDAR anchors each one in 3D.
5. **Plan:** the spoken goal becomes an ordered list of buttons (offline rules first, Claude for anything the rules do not understand).
6. **Guide the finger:** "Right... up... forward... press", with beeps that speed up like a parking sensor.
7. **Detect each press** (finger on the button and touching the panel for 0.4 s), confirm with a tone, and move to the next button: *"Pressed. Again, 0."* ... *"Microwave set for 2 minutes."*

### Elevator call panels
- **Two stacked buttons:** top is UP, bottom is DOWN. The app compares your current floor and destination floor to pick one.
- **One button:** it calls the elevator either way, so the app guides you to it.
- If you do not say your current floor, the app asks *"Which floor are you on now?"* and listens for the answer.
- Inside the elevator, press the Action button again and say the floor.

---

## How it works

| Step | Technology |
|---|---|
| Camera, world tracking, depth | ARKit (`ARWorldTrackingConfiguration`, LiDAR `sceneDepth`) |
| Fingertip tracking | Apple Vision hand pose (`VNDetectHumanHandPoseRequest`, index tip), on a background queue |
| Fingertip in 3D | LiDAR depth (closest value in a 5x5 window, so a thin finger is not missed) + pinhole camera unprojection + smoothing |
| Reading buttons | Claude vision (`claude-opus-5-5`) returns each button's label and center; Apple Vision OCR as an offline fallback |
| Buttons in 3D | Each button center + LiDAR depth becomes a world-space anchor, so labels stay locked on the real buttons as the phone moves |
| Goal planning | Offline rules (microwave times, floors, UP/DOWN/CALL) first, then Claude with a strict JSON schema; every label Claude returns is checked against the scanned buttons |
| Finger guidance | Panel frame (right, up, normal from gravity and the user's position); `target - fingertip` projected onto it gives dx, dy, dz |
| Press detection | Within 2.5 cm of the button and touching the panel for 0.4 s, with a short grace period for LiDAR noise; finger must lift before the same button counts again |
| Finding the panel | Apple Vision rectangle detection, filtered by real-world size (8 to 70 cm) computed from LiDAR distance and the camera focal length |
| Voice in | On-device speech recognition (`SFSpeechRecognizer`) |
| Voice and sound out | `AVSpeechSynthesizer` + `AVAudioEngine` sine-wave beeps (works with the silent switch on) |
| Eyes-free launch | `touchsight://listen` URL scheme (Shortcuts / Action button / Siri) and an App Intent |

### Project structure
```
TouchSight/
├── App/        Launch from the Action button, Siri, and Shortcuts
├── AR/         ARKit session, coordinate conversions, LiDAR depth
├── Vision/     Fingertip tracking, OCR button mapping, panel finder
├── AI/         Claude vision + goal planning clients, offline goal rules
├── Guidance/   Panel frame, guidance math, press detection, approach, coach
├── Feedback/   Speech and beeps
├── Speech/     Voice goal listener
├── Models/     PanelButton, GuidanceInstruction
└── UI/         Camera screen, debug overlay, button labels, fingertip dot
```

---

## Setup

**Requirements:** an iPhone with LiDAR (iPhone 12 Pro or newer Pro model), iOS 17+, Xcode, and an Anthropic API key.

1. Clone the repo and open `TouchSight.xcodeproj`.
2. Copy `Secrets.example.swift` to `TouchSight/AI/Secrets.swift` and paste your Anthropic API key. `Secrets.swift` is gitignored.
3. Select your Apple ID team under **Signing & Capabilities**, choose your iPhone, and press **Run**.
4. Allow camera, microphone, and speech recognition when asked.

**Action button / Siri:** in the Shortcuts app, create a shortcut with the **Open URLs** action set to `touchsight://listen`, name it "TouchSight Listen", and assign it in **Settings > Action Button > Shortcut**. Siri can run it by name.

**Security note:** for this hackathon demo the API key is compiled into the app. A production app would call Claude through a small backend so the key never ships on the device.

---

## AI tools used (disclosure)

Ensign BUILD asksed teams to be transparent about AI tools. TouchSight used:

- **Claude Code (Anthropic, model Claude Opus 5.5)** as a coding mentor during the event. We planned the milestones, explained Swift, ARKit, and Vision concepts, provided code snippets, reviewed and test-compiled the code, and helped debug. I typed about 60% of the code to learn Swift; Claude Code applied some fixes and refactors directly when asked, and drafted this README.
- **Claude API (`claude-opus-5-5`)** inside the app, for button detection from photos and for planning goals the offline rules do not understand.
- **Apple on-device machine learning** (Vision hand pose, text and rectangle detection, speech recognition) inside the app.

---

## Known limitations

- Speech recognition sometimes confuses similar-sounding numbers ("one" / "five") in noisy rooms.
- The panel finder can lock onto other panel-sized rectangles (signs, posters). Pointing the phone at the panel or tapping **AI Scan** works around it.
- Switching to a different panel by voice (for example from a microwave to an elevator) needs a fresh launch from the Action button so the old buttons are cleared.
- Claude scans need an internet connection; OCR and the offline rules work without one.

## Next steps

- Automatically detect the floor panel after stepping into the elevator.
- Panel type awareness (appliance vs. elevator) when switching panels by voice.
- Spatial audio and Apple Watch haptics for direction.
- Spanish voice mode.
- More panel types: ATMs, thermostats, kiosks, washing machines.

---

## Hackathon

- **Event:** Ensign BUILD 2026, Ensign College
- **Built:** October 9, 8:30 PM to October 10, 12:00 PM
- **Author:** Oliver Rivera ([@olael94](https://github.com/olael94))
