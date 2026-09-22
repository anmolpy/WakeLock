# WakeLock

An iOS 26 SwiftUI alarm app that helps you wake earlier and asks you to scan a
predetermined QR code to complete your wake-up routine.

## WakeLockCore increments

The core is a dependency-free Swift package. It contains rules we can test
without an iPhone before connecting them to SwiftUI, AlarmKit, and the camera.

```text
Core/
  Package.swift
  Sources/WakeLockCore/
    QRCodeTarget.swift
    WakePlan.swift
    WakePlanPersistence.swift
    WakeProgression.swift
    WakeSession.swift
    WakeTime.swift
  Tests/WakeLockCoreTests/
    WakePlanPersistenceTests.swift
    WakePlanTests.swift
    WakeProgressionTests.swift
    WakeSessionPersistenceTests.swift
    WakeLockCoreTests.swift
App/
  Models/     # Future SwiftUI state and app coordination
  Views/      # Future setup, alarm, and scanning screens
  Services/   # Future AlarmKit, camera, and persistence adapters
  Intents/    # Future alarm actions
```

`Core` imports Foundation only. It has no SwiftUI, AlarmKit, camera, or external
package dependencies, so the same rules can run on Linux and in the iOS app.
The `App` directories are placeholders; there is no Xcode app target yet.

### Increment 1: QR verification

`QRCodeTarget` is an immutable value containing the decoded text of the chosen
QR code. Its throwing initializer rejects blank text. It keeps valid text
unchanged and compares its UTF-8 bytes exactly, so changing case, whitespace,
or Unicode spelling does not accidentally accept a different payload. This
increment supports text QR payloads; it does not decode images or binary QR data.

`WakeSession` captures that target and an alarm identifier before the alarm
fires. Its states describe verification, not whether a sound is playing:

```text
waitingForAlarm -- alarmDidFire() --> awaitingScan -- correct scan --> completed
```

Scans before the alarm fires return `notReady`. Wrong scans return `wrongCode`
and leave the session awaiting a scan. Scans after completion return
`alreadyCompleted`. Repeated alarm events cannot reset the session. Each
occurrence of a repeating alarm needs a new session, even if its alarm ID is
unchanged.

`public private(set)` lets the app read the state but changes it only through
the core's methods. `mutating` means a method can update this struct, so the
session is declared with `var`. The target uses `let` so the required code
cannot be changed midway through a session. `Sendable` lets these values cross
Swift concurrency boundaries; the app will still need one owner for its mutable
session state.

```swift
import Foundation
import WakeLockCore

let target = try QRCodeTarget(payload: "wakelock:bathroom")
var session = WakeSession(alarmID: UUID(), target: target)

session.submitScan("wakelock:bathroom") // .notReady
session.alarmDidFire()
session.submitScan("wakelock:kitchen")  // .wrongCode
session.submitScan("wakelock:bathroom") // .completed
```

This is an in-memory rule, not a camera or scheduling implementation. A future
app coordinator must route alarm events to the correct occurrence and submit
text decoded by the scanner. Receiving matching text cannot prove physical
location or that someone is awake.

### Increment 2: moving the alarm earlier

`WakeTime` validates a wall-clock hour and minute. It deliberately contains no
date or time zone: AlarmKit will eventually combine it with a calendar when it
schedules the next occurrence.

`WakeProgression` describes a start time, an earlier target, and the number of
minutes to advance after each QR-verified wake session. It derives the current
time from a completed-session count instead of mutating itself. That makes the
result reproducible after a restart and prevents a duplicate event from causing
an extra step once persistence records each completion exactly once.

For a 7:30 start, 6:40 goal, and 15-minute step, the sequence is:

```text
completed sessions:  0      1      2      3      4+
wake time:          7:30   7:15   7:00   6:45   6:40
```

The last step is shortened to stop at the goal. A skipped or incomplete session
does not move the time earlier because it does not increase the verified count.
This policy treats times as positions within one day, so a target later than the
start is invalid; cross-midnight progressions are outside the current scope.

`WakePlan` connects the QR flow to this progression. It creates sessions with
the plan's alarm ID and QR target, then records a completed session by its own
unique ID. Alarm events may be delivered again after an app launch; recording
IDs makes that replay idempotent, so one wake-up cannot advance the schedule
twice.

### Increment 3: durable plan progress

`WakePlanSnapshot` converts a plan into versioned JSON containing its alarm ID,
QR payload, progression settings, and completed session IDs. Restoring goes
through every public validator again, so malformed persisted values cannot
bypass domain rules. The JSON encoder sorts keys and session IDs for stable,
reviewable output.

`WakePlanFileStore` writes this JSON atomically to a URL supplied by the app.
The iOS layer will choose a file in its Application Support directory. Atomic
writes prevent a killed process from leaving a partially written plan.

`WakeSessionSnapshot` and `WakeSessionFileStore` apply the same approach to the
active alarm occurrence. They preserve whether it is waiting for the alarm,
awaiting a scan, or already completed, along with the exact QR target captured
when that occurrence began. This lets the eventual app resume its verification
screen after relaunching.

### Build and test

Install a Swift 6.0 or newer toolchain using the
[official Swift installation instructions](https://www.swift.org/install/).
From the project root, run:

```sh
swift build --package-path Core
swift test --package-path Core
```

Tests cover target validation, exact matching, session transitions, wake-time
progression, duplicate completion delivery, JSON round trips, corrupted stored
values, and atomic file replacement. The repository pins Swift 6.4.0 in
`.swift-version` for Swiftly.

On macOS, use Xcode 26 or newer for the eventual iOS 26 app. Create a SwiftUI
iOS app target and add `Core` as a local package dependency, then link the
`WakeLockCore` product. The core package has no iOS minimum of its own; the app
target needs iOS 26 for AlarmKit.

### AlarmKit boundary

AlarmKit manages the system alarm UI and its Stop action. Apple's
[AlarmKit sample](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit)
documents that the system handles stopping the alarm when its Stop control is
used. A QR requirement can therefore gate WakeLock's recorded completion, but
we must not promise that scanning is the only way to silence an iOS alarm.
Stopping audio must not automatically mark a wake-up session completed.

The iOS integration will need alarm authorization and
`NSAlarmKitUsageDescription`. Camera scanning will also need its permission
flow and usage description. AlarmKit and camera behavior must be built with
Xcode and verified on an iPhone; Linux tests cover the core rules only.

### Next increments

1. Create the SwiftUI app in Xcode and integrate AlarmKit scheduling and state
   reconciliation, including alarms that fire while the app is not running.
2. Add QR enrollment and camera scanning, then exercise the full routine on an
   iPhone, including permissions, interruptions, and repeated alarms.
