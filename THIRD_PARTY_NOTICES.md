# Third-Party Notices

Noir bundles the unchanged native libraries from the canonical OpenTUI v0.5.1
release.

- Source: https://github.com/anomalyco/opentui
- Release: `v0.5.1`
- Pinned revision: `ad9a818d7a9d73f3386e92a445d0feb4b395c69e`

The release archives include OpenTUI and transitive notices for Wuffs,
libwebp, stb, and Little CMS. Their exact upstream files are published with
Noir:

- [OpenTUI license](third_party/opentui-v0.5.1/LICENSE)
- [Wuffs license](third_party/opentui-v0.5.1/LICENSE-WUFFS)
- [libwebp license](third_party/opentui-v0.5.1/LICENSE-LIBWEBP)
- [libwebp authors](third_party/opentui-v0.5.1/AUTHORS-LIBWEBP)
- [libwebp patent grant](third_party/opentui-v0.5.1/PATENTS-LIBWEBP)
- [stb license](third_party/opentui-v0.5.1/LICENSE-STB)
- [Little CMS license](third_party/opentui-v0.5.1/LICENSE-LCMS2)

These files were extracted from the official
`opentui-native-v0.5.1-darwin-arm64.zip` archive after its SHA-256 digest was
verified against the release manifest. The same notice files are present in
all six official platform archives.

## uucode and Unicode data

Noir incorporates a compact range table derived from the exact `uucode`
revision pinned by OpenTUI v0.5.1. The table applies OpenTUI's width rules to
that revision's Unicode 16.0 general-category and East Asian Width data.

- Source: https://github.com/jacobsandlund/uucode
- Pinned revision: `84ceda8561a17ba4a9b96ac5c583f779660bbd4e`
- [uucode MIT license](third_party/uucode-84ceda/LICENSE.md)
- [Unicode data license](third_party/uucode-84ceda/LICENSE_unicode)
