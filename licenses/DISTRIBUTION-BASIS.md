# Distribution basis

Decision date: 2026-08-31

The release owner has approved publication of this MLP1 port under GNU GPL
version 2. The upstream EULA is not accepted as a restriction on the
GPL-covered program and is not included in, or imposed as a condition of, the
binary package.

## Why the EULA is not the distribution basis

The EULA bundled in the pinned source prohibits modification, adaptation,
copying, distribution, resale, commercial use, third-party use, and licence
transfer. It also says modifications become devMiyax's property. Those terms
directly conflict with rights granted by GPLv2:

- Section 1 permits copying and redistribution, including charging for copies.
- Section 2 permits modification and redistribution of modified versions.
- Section 6 gives recipients the GPL rights and prohibits further restrictions.
- Section 7 says the program may not be distributed when conflicting
  obligations make GPL compliance impossible.

GPLv2 Section 4 also terminates a distributor's rights when the program is
copied, modified, sublicensed, or distributed outside the GPL's conditions.

The source is not represented as wholly owned by devMiyax. For example,
`yabause/src/bios.c` carries copyright notices for Theo Berkau and devMiyax and
licenses both contributions under GPL version 2 or later. The upstream
`yabause/AUTHORS` file names numerous other authors and contributors. One
contributor cannot unilaterally replace those other copyright holders' GPL
grants without their authorization, and no such authorization was found in the
pinned source.

The current website terms remain internally contradictory: section 8 says the
source may be used, modified, and redistributed under the GPL, while section 7
prohibits commercial use and asks that modified or redistributed source remain
non-commercial. The Google Play description likewise says Yaba Sanshiro 2 is
provided under the GPL.

- <https://www.yabasanshiro.com/terms-of-use> (accessed 2026-08-31)
- <https://play.google.com/store/apps/details?id=org.devmiyax.yabasanshioro2>
  (accessed 2026-08-31)

## Scope and distribution requirements

Separate terms can govern genuinely separate services, trademarks, branding,
or independently licensed assets when those components are clearly identified.
They cannot add restrictions to GPL-covered code. This package does not include
BIOS files, games, cloud services, or an EULA acceptance mechanism.

Any published binary must be accompanied by the corresponding source and the
UMRK patches and build scripts, or by a GPLv2-compliant written source offer. It
must retain copyright notices, the GPL text, and applicable third-party licence
notices. Recipients must receive the program without additional restrictions on
their GPL rights.

This file records the release owner's distribution decision and compliance
basis. It is not a court judgment or legal advice.
