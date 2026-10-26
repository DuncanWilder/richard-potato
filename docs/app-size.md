# App size measurements

Measured on 26 October 2026 with Apple Swift 6.4, macOS 27.0.1, the macOS
26.5 SDK, and an arm64 Release build. All counts below are bytes. Bundle size
is the sum of file lengths, not allocated disk blocks. Each bundle was signed
with the existing certificate and passed strict deep signature verification.
ZIPs use `ditto -c -k --keepParent` with the same `RichardPotato.app` name.
ZIP metadata can cause small differences between runs.

## Retained changes

| Stage | Executable | Icon | Complete app | ZIP | App saving from previous stage |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fresh baseline | 1,517,984 | 1,333,252 | 2,854,925 | 1,706,364 | — |
| Strip Release symbols | 658,608 | 1,333,252 | 1,995,549 | 1,575,246 | 859,376 |
| Add Release `-Osize` | 626,416 | 1,333,252 | 1,963,357 | 1,564,162 | 32,192 |
| Preserve the user's compressed icon PNGs | 626,416 | 652,228 | 1,282,333 | 851,317 | 681,024 |
| Apply approved 32-colour icon PNGs | 626,416 | 177,455 | 807,560 | 376,904 | 474,773 |

Code and build changes alone reduce the app by 31.2%. With the compressed
images available during the initial task, the complete reduction was 55.1%; the ZIP
reduction was 50.1%. The later approved 32-colour images bring the app below
1,000,000 bytes: 807,560 bytes for the signed app and 376,904 bytes for the ZIP.
The total reduction from the baseline is 71.7% for the app and 77.9% for the ZIP.

All ten PNGs in `AppIcon.appiconset` now use the reviewed 32-colour versions.
These were produced from copies of the current PNGs with `pngquant` 3.0.3,
`--speed 1 --strip`, a 32-colour limit and default Floyd–Steinberg dithering.
Pixel dimensions are unchanged. The original artwork under `artwork/` was preserved.

The user changed the icon PNGs during the investigation. The first three stages
and both UI trials use the original ICNS file, to keep the comparison fixed.
The PNG preservation stage uses the compressed PNGs present at measurement time. A plain
`iconutil` build with those PNGs still produced the original 1,333,252-byte icon.
The packaging helper preserves smaller PNG payloads instead of the larger
representations produced by `iconutil`. It retains the other ICNS chunks and
does not compress images or change their pixels.

`scripts/build.sh` strips only the staged Release executable with
`xcrun strip -S -x`, before signing. The SwiftPM build product retains its
symbols. Debug symbol handling is unchanged. The packaged executable must be
signed again after stripping, so a temporary unsigned-strip measurement is
slightly smaller than the final signed executable.

`Package.swift` applies `-Osize` to Release compilation and the Swift link driver,
as in the Blue Square investigation. This favours smaller code and can reduce
execution speed. No live dictation latency or CPU comparison was performed.

## Rejected UI trials

A linker map identified AnalyticsView and SettingsView as the largest source
contributors: 115,978 and 52,456 bytes of linked symbols in the recorded map.
These counts are not the savings available from removing those files.

Both trials below start from the stripped `-Osize` build, without other UI changes.
Both were reverted because they increased the executable and complete app size.

| Trial | Executable before | Executable after | App before | App after | ZIP before | ZIP after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Shared correction text field | 626,416 | 626,976 | 1,963,357 | 1,963,917 | 1,564,162 | 1,563,946 |
| Shared analytics tooltip | 626,416 | 626,448 | 1,963,357 | 1,963,389 | 1,564,162 | 1,563,744 |

The small ZIP reductions do not justify larger executables and additional view
types for this task. No view changes were retained.

## Reproduction

Build each stage through `./scripts/build.sh release`. Copy the signed bundle
to a separate temporary directory before the next build. Use the same bundle
name for each archive. Do not use a testable executable from `swift test` for
production size comparisons.

For the baseline, use the original manifest and omit the new strip and PNG
preservation steps. For the symbol stage, enable stripping only. For the
compiler stage, also enable both Release `-Osize` settings. Keep identical
icon data for all code comparisons. Measure PNG preservation last.

Create a linker map separately from the size build:

```sh
source scripts/toolchain.sh
xcrun swift build --sdk "$SDKROOT" -c release --product RichardPotato \
  -Xlinker -map -Xlinker /tmp/RichardPotato.map
```

Measure file lengths with `stat -f %z`. Sum the lengths of all regular files
for the bundle count. Use `ditto -c -k --keepParent` for the ZIP count.
Local comparison bundles, maps and JSON results for this run are in
`/tmp/richard-potato-size-study/`; they are temporary and are not committed.

The build consumes `RichardPotato/Assets.xcassets/AppIcon.appiconset/*.png`.
The images under `artwork/` are not direct build inputs.

## Validation

- `./scripts/check.sh` passed formatting, shell syntax, app metadata, Debug
  and Release compilation, and all five Debug tests.
- `./scripts/test.sh -c release` passed all five Release tests.
- Strict deep code signature checks passed for each measured app.
- The final ICNS file converted back to an iconset with `iconutil`. Its
  largest representation has the expected 1024 × 1024 dimensions. All eight
  preserved PNG payloads match the source files exactly.
- Repeating PNG preservation left the output unchanged. Invalid ICNS headers,
  incomplete chunk headers and out-of-bounds chunk lengths were rejected.
- No live microphone, Accessibility, speech installation or UI latency check
  was performed. Those actions still need a manual app check.
