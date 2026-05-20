# Reverie

A meditative macOS screensaver. Roulette curves — hypotrochoids and epitrochoids — draw themselves in dark ink across a pastel canvas, layering rotated copies of the same shape into dense rosettes. Underneath, animated waves flow toward the viewer over a digital horizon. Stroke colour breathes between two ink tones; backgrounds drift through twelve curated palettes; the whole composition is finished with a vignette and paper-grain texture so it reads as ink on paper rather than pixels on glass.

## Requirements

- macOS 14 (Sonoma) or later
- Universal binary (Apple Silicon and Intel)

## Installation

Download `Reverie.pkg` from the [latest release](https://github.com/PerpetualBeta/Reverie/releases/latest) and double-click it. The installer drops `Reverie.saver` into `/Library/Screen Savers/` (system-wide).

Then: **System Settings → Screen Saver → Reverie**.

To uninstall: System Settings → Screen Saver → pick anything else, then `sudo rm -rf "/Library/Screen Savers/Reverie.saver"`.

## What You'll See

Each cycle:

1. A pen begins drawing a curve from a single point. The path is a roulette — a hypotrochoid (small circle rolling inside a larger one) or an epitrochoid (small circle rolling outside) — chosen from a continuously-random parameter space.
2. When the curve closes, the pen lifts and the same shape is drawn again, rotated by a small angle. After 6–12 such passes (the count varies per cycle) the rosette is dense.
3. The completed composition holds for a few seconds, then fades. A new curve with a different lobe count begins immediately.
4. The colour pulse is independent of the curve cycle — strokes breathe back and forth between the palette's two ink tones over a slow 4-second sine wave.
5. The background palette drifts every 30 seconds through a 5-second Lab-space cross-fade, so the whole canvas slowly shifts hue.
6. Below the curve, an animated wavescape: 36 horizontal sine-wave lines stacked with linear perspective, scrolling toward the viewer at the bottom of the screen, undulating as they descend.

The brand contract is "no preferences", so there's nothing to configure — just watch.

## Architecture

- Pure Swift + Core Graphics. Single-binary build via `swiftc -emit-library`, packaged into a `.saver` bundle.
- One `ReverieView` per attached display, each with its own `ReverieEngine` so curves and palettes drift independently across screens.
- `Hypotrochoid.swift` is the curve generator: picks a closure denominator `q` from `{3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19}`, a coprime numerator `p < q`, a `d/r` ratio, and one of two families (hypo or epi). The last six `q` values are excluded from each pick so successive curves never share lobe count over a meaningful window.
- The rotation step between passes is one of three modes per cycle: symmetric (`2π / (q · passes)`), golden-angle (non-resonant), or random walk.
- Palettes hand-tuned: pastel backgrounds with darker "ink" stroke pairs (burgundy/navy, forest/indigo, plum/bronze, brand-blue/maroon, …). Cross-fades go via Lab space rather than RGB to avoid muddy mid-tones.
- Background-effect layers (ocean waves, vignette, paper grain) all draw inline in the same `CGContext` as the curve — no compositing layers, no offscreen buffers.

## Building from Source

Reverie's `Makefile` does double duty: dev-iteration targets for fast local work, plus the shared Jorvik `release.mk` (in the [`jorvik-release`](https://github.com/PerpetualBeta/jorvik-release) sibling repo) for full sign/notarise/package release builds. GNU Make 4+ is required (`brew install make` installs it as `gmake`; macOS bundles 3.81 which lacks the `.ONESHELL` and `.SHELLFLAGS` directives `release.mk` uses).

```bash
git clone https://github.com/PerpetualBeta/Reverie.git
cd Reverie
gmake dev-install      # arm64-only ad-hoc build → ~/Library/Screen Savers/
```

For visual iteration without re-installing the screensaver every time:

```bash
gmake run              # builds the test app, opens an NSWindow with the
                       # same engine the .saver uses
```

To rebuild the icon (a self-referential hypotrochoid in the brand colour):

```bash
swift generate_icon.swift
```

To produce a fully signed, notarised, and stapled `.pkg`:

```bash
gmake release          # → .build/Reverie.pkg
```

The dev targets use ad-hoc signing for speed and are suitable for personal installation. The `release` target performs Developer ID signing and notarisation through the shared `release.mk` pipeline; Release Manager invokes the same target when cutting an official release.

## Updates

Reverie ships as manual `.pkg` downloads — there's no in-app updater. macOS screensavers don't have the right lifecycle for Sparkle (no persistent process, no menu to host a "Check for Updates" command). Watch the [Releases page](https://github.com/PerpetualBeta/Reverie/releases) for new versions, or the [Jorvik Software](https://jorviksoftware.cc/) blog.

---

Reverie is provided by [Jorvik Software](https://jorviksoftware.cc/). Public Domain — do whatever you like with it.
