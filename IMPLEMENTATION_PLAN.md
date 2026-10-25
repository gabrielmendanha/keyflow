# Keyflow implementation plan

## Product scope

Keyflow is a native macOS menu bar app for the supported `1189:8890` macropad. The primary
interface is a compact floating panel anchored to the menu bar item; it has no main window.

The approved visual direction is a borderless floating `NSPanel` hosted with SwiftUI, using AppKit's
semantic popover material: a minimal header with connection state, selectable profile rows, an
automatic-switching control, and a clear **Quit Keyflow** action. Do not show a Current Focus section
or decorative icons in the panel. Focus monitoring remains internal to automatic profile matching.
Do not add a settings gear unless a real settings feature is later agreed.

The agreed features are:

- Show whether the macropad is connected.
- Automatically apply the matching profile after focus settles.
- Let the user select an installed profile manually.
- Let the user pause and resume automatic switching.
- Load profile definitions from YAML maintained in this repository and contributed through pull
  requests. There is no in-app profile creation or profile editor.
- Show clear connection, permission, and write-error states.

## Current baseline

- A Swift/AppKit menu bar app with a SwiftUI view hosted in a floating `NSPanel`; the app bundle
  builds with `build.sh`.
- Device discovery is separated into `PadMonitor` and `DeviceStatus`. IOKit attach/detach
  notifications update connection state, with a 30-second reconciliation scan.
- Connection appears only as compact Connected/Not connected text in the panel header and
  menu bar item; there is no separate device-status panel or last-seen display. A visible Quit
  action exits the app.
- Profile rows load from the bundled, versioned YAML catalog and show their matching rules. Manual
  and automatic selection apply mappings through the bundled libusb transport.
- The current frontmost app name and bundle ID are read from `NSWorkspace`. Chrome's active tab URL
  is queried after the configured settle interval and site rules can select a matching profile.
  Window-title matching remains a future phase.
- The configuration channel is the pad's raw USB interrupt OUT endpoint `0x02`, not a HID report.
  The device cannot report its saved mappings back to the app.

## Implementation phases

### 1. Stabilize the app shell and device lifecycle

- Split implemented concerns into app/menu presentation and device discovery/status components.
  Keep future device transport, profile models, focus reader, and switching coordinator in
  separate components as those phases are added.
- Keep the compact connected/disconnected indicator current in the menu bar item and popover
  header. Do not duplicate it in a device-details panel.
- Replace repeated full USB scans with attach/detach notifications if the platform API supports
  reliable matching for this device; retain a low-frequency reconciliation scan as recovery.
- Verify behavior on unplug/replug and app restart. No input or Accessibility permission should be
  needed just to report device presence.

**Done when:** the status follows physical connect/disconnect reliably, the menu stays responsive,
and device discovery is isolated from profile or focus logic.

**Implementation status:** code and build are complete. The user confirmed that connected and
disconnected states are recognized on the physical pad. App restart behavior has not been
explicitly verified.

### 2. Define and load the YAML profile catalog

- Specify a versioned schema for named profiles, layout files, focus rules, and an optional default.
  Reuse the existing layout/action vocabulary where it fits.
- Bundle the reviewed YAML catalog and referenced layout files in the app. A profile PR updates
  those source files; a released app version delivers the new catalog. Do not add a create/edit UI.
- Select a maintained Swift YAML decoder rather than hand-writing a general-purpose YAML parser.
  Pin the dependency and validate the supported schema strictly at load time.
- Report malformed profiles and unknown actions without silently applying a different mapping.
- Show installed profiles and their matching rule in the panel; allow a manual selection.

**Done when:** every bundled profile loads with actionable validation errors, manual selection
updates the active profile display, and the catalog remains reviewable as ordinary YAML in Git.

**Implementation status:** complete. The bundled catalog has 2 profiles and 6 rules, validates
successfully, and manual selection updates the popover. The YAML decoder is pinned to Yams 6.2.2.

### 3. Add app-focus detection and app rules

- Observe frontmost application changes with `NSWorkspace` activation notifications.
- Match app rules by bundle identifier, with localized app name as a convenient secondary match.
- Add a configurable settle interval (initial default: 0.5 seconds) before acting on a new focus.
- Keep detected-app and matching details internal. The popover shows profile names and their
  configured matching rules, without a Current Focus section or a Selected label.
- Keep app matching available without Accessibility or Automation permission.

**Done when:** switching between two configured apps selects the right profile after the settle
interval, while rapid focus changes do not cause intermediate writes.

**Implementation status:** focus notifications, app-name/bundle-ID matching, settle cancellation,
fallback behavior, and automatic/manual selection are implemented. The popover intentionally keeps
focus details internal; it shows profile names and matching rules only. Interactive app-switch
behavior has not been manually verified in this session.

### 4. Add safe native profile application

- Implement the packet encoder in Swift from the documented protocol and verify expected packet
  bytes independently against the existing Python implementation and protocol documentation.
- Spike and validate raw access to interface 1 / interrupt OUT endpoint `0x02` from the app. Keep
  this transport behind a narrow interface so USB API decisions do not leak into profile logic.
- Write only slots that differ from the app's recorded state. On first launch or whenever state is
  uncertain, apply the complete target profile because the device cannot be read back.
- Persist the last successfully applied layout only after all writes succeed. If a write fails
  partway, mark device state unknown and fully apply the next target profile.
- Serialize writes, coalesce focus changes during a write, and avoid retry loops that repeatedly
  write flash while the device is unavailable.

**Done when:** changing focus applies the target mapping on real hardware, unchanged slots are not
rewritten, and partial failures recover by reapplying a complete profile.

**Implementation status:** packet encoding, bundled libusb transport, serialized and coalesced
writes, changed-slot diffing, persisted last-successful state, and unknown-state recovery are
implemented. The release build succeeded, and a full 35-packet X Social profile write completed on
the connected macropad. Physical keypress confirmation and partial-write recovery still need checks.

### 5. Complete website matching and add optional window-title rules

- First, connect the Automatic switching control to focus matching so it truly pauses and resumes
  automatic profile changes. When resumed, reevaluate the current focus after the settle interval.
- Add window-title matching through macOS Accessibility APIs. Explain the permission requirement
  and keep app-level matching available if Accessibility permission is denied.
- Finish Chrome site matching: detect and communicate Automation permission state clearly, and
  provide a direct path to the relevant macOS Privacy & Security setting. Keep app-level matching
  available when permission is denied.
- Add another browser only when its URL lookup behavior and support are defined. Request Automation
  permission only when a configured site rule needs that browser; a refusal must not stop app rules.
- Keep browser lookups bounded and ensure slow or denied lookups cannot stall focus handling.

**Implementation status:** Google Chrome active-tab URL lookup, host matching (including
subdomains), and one-second URL polling are implemented. The lookup has a two-second timeout.
macOS requests Automation permission when Chrome site rules need it; denial leaves app-level rules
available. The Automatic switching control now pauses/resumes focus matching and reapplies the
current focus after the settle interval when resumed. The permission-needed message exists in
internal match status but is not shown in the popover. Window-title matching, user-visible
permission guidance/settings access, and support for additional browsers remain pending. YAML
accepts title conditions, but the focus matcher does not evaluate them yet.

**Done when:** the Automatic switching control pauses and resumes matching; Chrome site rules match
hosts and subdomains; title rules work with the required Accessibility permission; any additional
browser explicitly marked supported matches its site rules; and denied or slow permission/lookups
leave app-level matching responsive.

### 6. Finish the menu bar interaction and release

- Keep the approved floating `NSPanel`/SwiftUI panel minimal: a Connected/Not connected badge with
  red/green status dots, profile rows, the automatic-switching control, and a quit icon. Keep the
  popover arrowless and omit Current Focus, a Selected label, decorative profile icons, and a
  settings gear.
- The quit icon terminates the menu bar app; closing the panel alone must not quit it.
- Manual profile selection remains effective across apps with no matching rule; a matching app
  rule or configured default returns selection to automatic when automatic switching is enabled.
- Provide onboarding for first launch, no connected pad, no valid profiles, and optional permission
  setup. Keep all routine use in the menu bar panel.
- Add launch-at-login only after the core switching behavior is stable and the user can reliably
  pause or quit the app.
- Add bundle versioning, Developer ID signing/notarization, and a clean install/update path. A
  custom six-key macropad and knob icon is now included in the app bundle.

**Implementation status:** the minimal floating panel, connection badge, profile rows, native
popover material, arrowless positioning, quit icon, and bundled app/menu-bar icon are implemented.
Empty/error profile states and mapping-write errors have basic in-panel messages. First-run
onboarding, user-facing permission recovery, launch at login, signing/notarization, and a clean
install/update path remain pending.

**Done when:** the app is usable without a terminal with clear recovery guidance, and it can be
installed and launched as a signed menu bar app.

## Cross-cutting verification

- Unit tests for YAML validation, rule matching, settle/coalescing behavior, packet bytes, diffing,
  and failure recovery. Expected packet bytes should be derived from the protocol document, not
  generated by the encoder under test.
- Hardware-free tests should fake only the focus and USB boundaries; keep profile and switching
  logic real.
- Manual hardware checks for connect/disconnect, first full apply, app switches, manual selection,
  unplug during write, and recovery after reconnect.
- Permission checks on a clean macOS user account for Accessibility and browser Automation.
- Build checks for the minimum supported macOS version, Apple silicon, and Intel if universal
  distribution is a goal.

## Decisions to settle before implementation

1. **Profile delivery:** this plan assumes YAML profiles are bundled in app releases after PR
   review. If users should receive merged profiles without installing a new app version, choose a
   hosted catalog/update mechanism instead.
2. **Manual selection precedence:** resolved: a manual choice persists until focus matches an app
   rule or configured default; unmatched apps keep the current selection.
3. **Minimum macOS and CPU support:** the current app bundle declares macOS 13+ and builds for the
   machine's native architecture; distribution targets may require a universal binary.
4. **USB write transport:** complete the endpoint-access spike before committing the app to a
   transport implementation or release schedule.
