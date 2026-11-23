#!/bin/bash
# lr-autostraighten.sh  (v4)
# Runs Lightroom Classic's Crop tool "Auto" straighten on a run of photos.
#
# Usage:   ./lr-autostraighten.sh [COUNT] [WAIT_SECONDS]
#   COUNT         how many photos to process, starting at the selected one (default 10)
#   WAIT_SECONDS  pause after pressing Auto so Lightroom can finish (default 2.5)
#
# Before you run it:
#   1. Lightroom Classic is open in the Develop module.
#   2. Select the FIRST photo you want straightened. The Crop tool can be open
#      or closed - the script checks and only presses R when it's closed.
#      It works rightward from there, in the order the filmstrip shows.
#   3. Terminal has Accessibility permission:
#      System Settings > Privacy & Security > Accessibility > enable Terminal.
#   4. Xcode command line tools are installed (run `xcode-select --install` if
#      you get a "swiftc: command not found" error).
#
# Don't touch the mouse or keyboard while it runs. Ctrl+C stops it.
# Each crop can be undone in Lightroom with Cmd+Z.

COUNT="${1:-10}"
WAIT="${2:-2.5}"
BUNDLE="com.adobe.LightroomClassicCC7"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
  echo "COUNT must be a positive whole number." >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install the command line tools: xcode-select --install" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helper: `lrcrop state` -> exit 0 if the Crop tool is open, 1 if closed.
#         `lrcrop press` -> presses the Crop panel's Auto button (exit 1 if Crop is closed).
# It finds the Crop panel by its "Constrain to Image" checkbox, so it never
# touches the Basic panel's Auto (tone) button.
cat > "$WORK/lrcrop.swift" <<'SWIFT'
import Cocoa
import ApplicationServices

let bundleID = "com.adobe.LightroomClassicCC7"
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "state"

guard AXIsProcessTrusted() else {
    fputs("Terminal does not have Accessibility permission (System Settings > Privacy & Security > Accessibility).\n", stderr)
    exit(3)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fputs("Lightroom Classic is not running.\n", stderr)
    exit(4)
}
let appEl = AXUIElementCreateApplication(app.processIdentifier)

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func kids(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}
func label(_ el: AXUIElement) -> String {
    (attr(el, kAXTitleAttribute as String) as? String)
        ?? (attr(el, kAXDescriptionAttribute as String) as? String) ?? ""
}
func role(_ el: AXUIElement) -> String { (attr(el, kAXRoleAttribute as String) as? String) ?? "" }

// Search one window's tree; return its Crop "Auto" button if the window holds the Crop panel.
func cropAuto(in window: AXUIElement) -> AXUIElement? {
    var hasConstrain = false
    var autoButtons: [AXUIElement] = []
    var stack: [(AXUIElement, Int)] = [(window, 0)]
    var visited = 0
    while visited < 5000, let item = stack.popLast() {
        let (el, depth) = item
        visited += 1
        let r = role(el), l = label(el)
        if r == "AXCheckBox" && l == "Constrain to Image" { hasConstrain = true }
        if r == "AXButton" && l == "Auto" { autoButtons.append(el) }
        if depth < 15 { for k in kids(el) { stack.append((k, depth + 1)) } }
    }
    guard hasConstrain, !autoButtons.isEmpty else { return nil }
    // If more than one titled Auto shows up, the Crop one is the highest on screen.
    func y(_ e: AXUIElement) -> CGFloat {
        guard let v = attr(e, kAXPositionAttribute as String) else { return .greatestFiniteMagnitude }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p.y
    }
    return autoButtons.min { y($0) < y($1) }
}

var windows = (attr(appEl, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
windows += kids(appEl).filter { role($0) == "AXWindow" }

var target: AXUIElement?
for w in windows { if let b = cropAuto(in: w) { target = b; break } }

if mode == "state" { exit(target == nil ? 1 : 0) }

guard let button = target else {
    fputs("Crop tool isn't open, so there's no Crop Auto button to press.\n", stderr)
    exit(1)
}
let rc = AXUIElementPerformAction(button, kAXPressAction as CFString)
if rc != .success { fputs("Pressing Auto failed (\(rc.rawValue)).\n", stderr); exit(6) }
SWIFT

echo "Compiling helper..."
if ! swiftc -O -o "$WORK/lrcrop" "$WORK/lrcrop.swift" 2>"$WORK/compile.log"; then
  echo "Helper failed to compile:" >&2
  cat "$WORK/compile.log" >&2
  exit 1
fi

key() { osascript -e "tell application \"System Events\" to key code $1" >/dev/null; }

# Wait (up to ~4s) for the Crop tool to reach the wanted state: open|closed
wait_for() {
  for _ in $(seq 1 20); do
    "$WORK/lrcrop" state; local s=$?
    [ $s -ge 3 ] && exit $s
    if [ "$1" = open ] && [ $s -eq 0 ]; then return 0; fi
    if [ "$1" = closed ] && [ $s -eq 1 ]; then return 0; fi
    sleep 0.2
  done
  return 1
}

echo "Straightening $COUNT photo(s), waiting ${WAIT}s after each Auto press."
echo "Starting in 3 seconds. Don't touch the keyboard or mouse. Ctrl+C to stop."
sleep 3

osascript -e "tell application id \"$BUNDLE\" to activate" >/dev/null
sleep 1

for ((i = 1; i <= COUNT; i++)); do
  # Open the Crop tool only if it isn't already open (R toggles it).
  "$WORK/lrcrop" state; s=$?
  [ $s -ge 3 ] && exit $s
  if [ $s -ne 0 ]; then
    key 15                                     # R: open the Crop tool
    if ! wait_for open; then
      echo "Stopped on photo $i: the Crop tool didn't open." >&2
      exit 1
    fi
  fi

  if ! "$WORK/lrcrop" press; then
    echo "Stopped on photo $i: couldn't press the Crop panel's Auto button." >&2
    exit 1
  fi
  sleep "$WAIT"                                # let Lightroom finish the angle

  key 36                                       # Return: confirm the crop
  if ! wait_for closed; then
    echo "Stopped on photo $i: the crop didn't confirm." >&2
    exit 1
  fi

  echo "Done $i / $COUNT"
  if [ "$i" -lt "$COUNT" ]; then
    key 124                                    # right arrow: next photo
    sleep 0.8
  fi
done

echo "All done."
