#!/bin/sh

set -eu

error_count=0

fail() {
  error_count=$((error_count + 1))
  printf 'ERROR: %s\n' "$1"
}

ok() {
  printf 'OK: %s\n' "$1"
}

require_env() {
  name="$1"
  value="$(eval "printf '%s' \"\${$name:-}\"")"
  if [ -n "$value" ]; then
    ok "$name is set."
  else
    fail "$name is required."
  fi
}

is_http_url() {
  case "$1" in
    https://*|http://*) return 0 ;;
    *) return 1 ;;
  esac
}

is_placeholder() {
  case "$1" in
    *YOUR_*|*your_*|*example.com*|*localhost*|*127.0.0.1*|*0.0.0.0*) return 0 ;;
    *) return 1 ;;
  esac
}

printf 'Final external Kaggle submission check\n'
printf 'Checking live project/video fields that local CI cannot prove...\n\n'

require_env KAGGLE_PROJECT_LINK
require_env KAGGLE_YOUTUBE_URL
require_env KAGGLE_VIDEO_DURATION_SECONDS
require_env KAGGLE_MEDIA_GALLERY_CONFIRMED
require_env KAGGLE_TRACK_CONFIRMED
require_env KAGGLE_WRITEUP_READY_CONFIRMED
require_env KAGGLE_PRIVATE_RESOURCES_CONFIRMED

project_link="${KAGGLE_PROJECT_LINK:-}"
youtube_url="${KAGGLE_YOUTUBE_URL:-}"
video_duration="${KAGGLE_VIDEO_DURATION_SECONDS:-}"
media_gallery_confirmed="${KAGGLE_MEDIA_GALLERY_CONFIRMED:-}"
track_confirmed="${KAGGLE_TRACK_CONFIRMED:-}"
writeup_ready_confirmed="${KAGGLE_WRITEUP_READY_CONFIRMED:-}"
private_resources_confirmed="${KAGGLE_PRIVATE_RESOURCES_CONFIRMED:-}"

if [ -n "$project_link" ]; then
  if is_http_url "$project_link" && ! is_placeholder "$project_link"; then
    ok "KAGGLE_PROJECT_LINK looks like a public URL."
  else
    fail "KAGGLE_PROJECT_LINK must be a real public http(s) URL, not a placeholder or localhost URL."
  fi
fi

if [ -n "$youtube_url" ]; then
  case "$youtube_url" in
    https://www.youtube.com/watch*|https://youtube.com/watch*|https://youtu.be/*)
      if ! is_placeholder "$youtube_url"; then
        ok "KAGGLE_YOUTUBE_URL looks like a YouTube video URL."
      else
        fail "KAGGLE_YOUTUBE_URL still looks like a placeholder."
      fi
      ;;
    *)
      fail "KAGGLE_YOUTUBE_URL must be a YouTube watch URL or youtu.be URL."
      ;;
  esac
fi

if [ -n "$video_duration" ]; then
  case "$video_duration" in
    ''|*[!0-9]*)
      fail "KAGGLE_VIDEO_DURATION_SECONDS must be an integer from 1 to 300."
      ;;
    *)
      if [ "$video_duration" -ge 1 ] && [ "$video_duration" -le 300 ]; then
        ok "KAGGLE_VIDEO_DURATION_SECONDS is within the 5-minute limit."
      else
        fail "KAGGLE_VIDEO_DURATION_SECONDS must be 300 seconds or less."
      fi
      ;;
  esac
fi

if [ "$media_gallery_confirmed" = "yes" ]; then
  ok "KAGGLE_MEDIA_GALLERY_CONFIRMED is yes."
else
  fail "Set KAGGLE_MEDIA_GALLERY_CONFIRMED=yes after attaching the cover image and YouTube video to Kaggle."
fi

if [ "$track_confirmed" = "Concierge Agents" ]; then
  ok "KAGGLE_TRACK_CONFIRMED is Concierge Agents."
else
  fail "Set KAGGLE_TRACK_CONFIRMED='Concierge Agents' after selecting the Kaggle track."
fi

if [ "$writeup_ready_confirmed" = "yes" ]; then
  ok "KAGGLE_WRITEUP_READY_CONFIRMED is yes."
else
  fail "Set KAGGLE_WRITEUP_READY_CONFIRMED=yes after the Kaggle Writeup has title, subtitle, selected track, body, Media Gallery, project link, and is ready to submit."
fi

if [ "$private_resources_confirmed" = "yes" ]; then
  ok "KAGGLE_PRIVATE_RESOURCES_CONFIRMED is yes."
else
  fail "Set KAGGLE_PRIVATE_RESOURCES_CONFIRMED=yes after confirming no unintended private Kaggle Resources are attached."
fi

if [ -f docs/submission/KAGGLE_WRITEUP_DRAFT.md ]; then
  writeup_words=$(wc -w < docs/submission/KAGGLE_WRITEUP_DRAFT.md | tr -d ' ')
  if [ "$writeup_words" -le 2500 ]; then
    ok "Local-only Kaggle writeup draft is under 2,500 words ($writeup_words words)."
  else
    fail "Local-only Kaggle writeup draft is over 2,500 words ($writeup_words words)."
  fi
else
  ok "Local-only Kaggle writeup draft is not present; relying on KAGGLE_WRITEUP_READY_CONFIRMED."
fi

printf '\nFinal external submission check complete: %s errors.\n' "$error_count"

if [ "$error_count" -gt 0 ]; then
  printf 'Fill in the real Kaggle submission URLs and confirmations above before submitting.\n'
  exit 1
fi
