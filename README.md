# LibassBuild

libass for tvOS as one static xcframework, consumed by Rivulet through SwiftPM.

| Library | Version | Licence |
|---|---|---|
| libass | 0.17.5 | ISC |
| FreeType | VER-2-14-3 | FreeType License (FTL), chosen from its FTL or GPLv2 dual licence |
| HarfBuzz | 14.2.0 | Old MIT |
| FriBidi | v1.0.16 | LGPL 2.1 or later, used under LGPL 2.1 |
| libunibreak | libunibreak_6_1 | zlib |

Licence texts are in `LICENSES/`. The build scripts are MIT (`LICENSE`); the meson
options follow mpvkit/libass-build (MIT).

## Source

`build.sh` clones each library from its upstream repository at the tag above and
applies no patches. FriBidi's corresponding source is therefore
https://github.com/fribidi/fribidi at tag v1.0.16, and relinking against a modified
FriBidi is `build.sh` with that tag replaced.

## Build

Needs Xcode with the tvOS SDKs, meson, ninja and pkg-config.

    ./build.sh
    swift package compute-checksum dist/Libass.xcframework.zip

Put the checksum in `Package.swift`, commit, tag `<libass version>-<build revision>`
(for example `0.17.5-1`), and attach `dist/Libass.xcframework.zip` to the release
of that tag. Never move a published tag: SwiftPM records each tag's revision and
refuses one that changes.

The module map lives in `Support/`, never at the package root: SwiftPM treats a
root `module.modulemap` as a legacy system-library package and ignores the
binary target. Inside the xcframework it sits in `Headers/Libass/`, never at the
`Headers` root: Xcode copies every static xcframework's headers into one shared
`include/` directory, and two root module maps collide.
