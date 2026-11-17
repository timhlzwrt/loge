# Third-party files

Other projects' logos and licences that ship in the app. `Logos.xcassets` is kept apart from
`Assets.xcassets` because `Tools/render-icons.swift` deletes and rewrites that catalog.

## TMDB logo

`Logos.xcassets/TMDBLogo.imageset/tmdb.svg` is the unmodified approved “Alt short” logo from
https://www.themoviedb.org/about/logos-attribution, downloaded on 2026-11-02:

https://www.themoviedb.org/assets/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg

The asset renders as a white template. TMDB expressly permits white logos in its
branding requirements: https://developer.themoviedb.org/docs/faq . Its proportions
and shape are unchanged. The app's Credits section includes the required notice
and links to https://www.themoviedb.org .

## IMDb mark

`Logos.xcassets/ScoreIMDb.imageset/imdb.svg` is IMDb's plate from Wikimedia Commons with the
lettering merged into one even-odd path, because a template image keeps only alpha.

## Sparkle

`Sparkle-LICENSE.txt` is Sparkle's licence, bundled with the Mac app only (see `project.yml`).
