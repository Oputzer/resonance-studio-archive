<p align="center">
  <img src="assets/logo.png" alt="FMF — Free Music Foundation" width="420">
</p>

<p align="center">
  A native Mac app that saves public SoundCloud playlists to your Mac, with cover art and full song details, in the format you want.
</p>

<p align="center">
  <img src="assets/screenshot-download.png" alt="FMF new download screen" width="800">
</p>

## Features

- **Paste a link, get the playlist.** Works with public SoundCloud playlists and single songs.
- **Five formats.** Original (the untouched source stream, best quality), MP3 320 kbps, AAC, WAV, and FLAC.
- **Cover art built in.** Full-resolution artwork is embedded in every MP3, AAC, and FLAC file, and saved as `cover.jpg` in each playlist folder.
- **Rich song details.** Artist, genre, upload date, plays, likes, reposts, license, and description from SoundCloud. When a song is also in Apple's music catalog, FMF adds the official album name, release date, track number, and a high-resolution album cover.
- **A real library.** Browse every playlist you've saved, see song details in an info panel, and play songs right inside the app.
- **A simple folder system.** Everything lives in an `FMF` folder on your Desktop, created automatically, with one folder per download, named with the playlist and the date:

  ```
  Desktop/
  └── FMF/
      └── Late Night Drive — 2026-11-18/
          ├── 01 - First Song.mp3
          ├── 02 - Second Song.mp3
          └── cover.jpg
  ```

  Click **Show in Finder** on any playlist or song to jump straight to it.
- **No 30-second clips.** Songs that SoundCloud only offers as a Go+ preview are skipped and listed, instead of being saved as a clip.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org):

  ```sh
  brew install yt-dlp ffmpeg
  ```

  If SoundCloud downloads stop working, update yt-dlp with `brew upgrade yt-dlp`.

## Build

FMF builds with the Xcode Command Line Tools. Xcode itself is not required.

```sh
git clone https://github.com/Oputzer/fmf.git
cd fmf
scripts/build-app.sh
open build/FMF.app
```

To install it, drag `build/FMF.app` into your Applications folder. The app is not notarized, so the first time you open it, right-click it and choose **Open**.

## Accounts and backend

FMF asks people to accept the [Terms of Use](legal/TERMS.md) and sign in with their email (a one-time code, no password) before using it. Sign-in and the download log use [Supabase](https://supabase.com):

1. Create a Supabase project and run [`supabase/schema.sql`](supabase/schema.sql) in its SQL editor.
2. In **Authentication › Email Templates › Magic Link**, include `{{ .Token }}` so the email contains a 6-digit code.
3. Copy `Config/backend.env.example` to `Config/backend.env` and fill in your project URL and publishable key.
4. Run `scripts/build-app.sh` again.

Without a backend, FMF runs as a local test build and stores the email only on the Mac.

## Project layout

```
Sources/FMF/
├── App/        App entry point
├── Models/     Formats, songs, playlists
├── Services/   Downloading, library, catalog lookup, accounts, playback
└── Views/      SwiftUI interface
legal/          Terms of Use and Privacy Policy
scripts/        Build scripts
supabase/       Database schema
web/            The original single-page web version
```

## Legal

FMF is a tool. You are responsible for what you download with it. Only download content you own, that the rights holder has made available for download, or that you otherwise have the right to copy. Using FMF means you accept the [Terms of Use](legal/TERMS.md), including the assumption of all risk.

FMF is an independent project and is not affiliated with, endorsed by, or sponsored by SoundCloud, Apple, or Spotify.

Code released under the [MIT License](LICENSE).
