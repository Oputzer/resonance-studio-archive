# Playlist Zipper

Local site: paste a public SoundCloud playlist/track link → pick a format → download a zip.

- Start: double-click `Start Playlist Zipper.command` (or `npm start`), then open http://localhost:4321
- Needs: `brew install yt-dlp ffmpeg` (keep yt-dlp fresh with `brew upgrade yt-dlp` if SoundCloud stops working)
- Formats: Original (no re-encode, true max quality), MP3 320, AAC, WAV, FLAC
- Only reachable from this Mac (binds 127.0.0.1). Job files auto-delete after 1 hour and on restart.
