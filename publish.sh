#!/usr/bin/env bash
# Publish one GitHub release's notes to a SlopIt blog, as written.
# Reads the release from $GITHUB_EVENT_PATH (a `release` event: `published`,
# or `edited` to update the post after the notes change).
set -euo pipefail

fail() { echo "::error::$*"; exit 1; }
out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT" || true; }

[ -n "${SLOPIT_API_KEY:-}" ] || fail "api-key is empty. Add the blog's API key as a repository secret and pass it as api-key."
echo "::add-mask::${SLOPIT_API_KEY}"
[ -f "${GITHUB_EVENT_PATH:-}" ] || fail "No event payload. Run this action on 'release: types: [published]'."
API="${INPUT_API_BASE:-https://slopit.io/api}"
API="${API%/}"

ev="$GITHUB_EVENT_PATH"
# Manual run (workflow_dispatch with a `tag` input): fetch that release from
# the GitHub API and treat it like a release event. Use it to republish a
# release after editing its notes.
if ! jq -e '.release' "$ev" >/dev/null; then
  tag_in="${INPUT_TAG:-$(jq -r '.inputs.tag // empty' "$ev")}"
  [ -n "$tag_in" ] || fail "Not a release event and no tag given. Use on: release: types: [published], or run the workflow manually with a tag."
  [ -n "${GH_TOKEN:-}" ] || fail "A manual run needs GH_TOKEN (pass github-token: \${{ github.token }})."
  rel=$(curl -sS --fail-with-body -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" \
    "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/releases/tags/${tag_in}") || fail "Couldn't fetch release ${tag_in}: $rel"
  ev=$(mktemp)
  jq -n --argjson r "$rel" --arg name "${GITHUB_REPOSITORY#*/}" --arg full "$GITHUB_REPOSITORY" \
    '{release: $r, repository: {name: $name, full_name: $full}}' > "$ev"
fi

draft=$(jq -r '.release.draft' "$ev")
pre=$(jq -r '.release.prerelease' "$ev")
tag=$(jq -r '.release.tag_name' "$ev")
repo=$(jq -r '.repository.name' "$ev")
url=$(jq -r '.release.html_url' "$ev")
rid=$(jq -r '.release.id' "$ev")
name=$(jq -r '.release.name // ""' "$ev")
notes=$(jq -r '.release.body // ""' "$ev")

if [ "$draft" = "true" ]; then echo "Draft release, skipped."; out post-url ""; exit 0; fi
if [ "$pre" = "true" ] && [ "${INPUT_INCLUDE_PRERELEASES:-false}" != "true" ]; then
  echo "Prerelease, skipped (set include-prereleases: true to post these)."; out post-url ""; exit 0
fi

title="${INPUT_TITLE:-}"
[ -n "$title" ] || title="$name"
[ -n "$title" ] || title="$repo $tag"
prefix="${INPUT_SLUG_PREFIX:-$repo}"
slug=$(printf '%s-%s' "$prefix" "$tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-80 | sed -E 's/-+$//')
[ -n "$slug" ] || fail "Couldn't build a slug from '$prefix' and '$tag'."

[ -n "$(printf '%s' "$notes" | tr -d '[:space:]')" ] || notes="No notes were written for this release."
body=$(printf '%s\n\n---\n\n[%s on GitHub](%s)\n' "$notes" "$tag" "$url")

auth=(-H "Authorization: Bearer ${SLOPIT_API_KEY}")
me=$(curl -sS --fail-with-body "${auth[@]}" "$API/me") || fail "GET $API/me failed: $me"
blog=$(printf '%s' "$me" | jq -r '.blog_id // .blog.id // empty')
[ -n "$blog" ] || fail "Couldn't read the blog id from $API/me."

tags_json=$(printf '%s' "${INPUT_TAGS:-release,changelog}" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')
payload=$(jq -nc --arg t "$title" --arg s "$slug" --arg b "$body" --arg st "${INPUT_STATUS:-published}" \
  --arg ex "Release notes for $repo $tag." --argjson tags "$tags_json" \
  '{title:$t, slug:$s, body:$b, status:$st, excerpt:$ex, tags:$tags}')

resp_file=$(mktemp)
code=$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "${auth[@]}" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gh-release-${rid}-$(printf '%s' "$payload" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-16)" \
  --data "$payload" "$API/blogs/$blog/posts")
resp=$(cat "$resp_file")

if [ "$code" = "409" ] && printf '%s' "$resp" | jq -e '.error.code == "POST_SLUG_CONFLICT"' >/dev/null 2>&1; then
  if [ "${INPUT_UPDATE_EXISTING:-true}" != "true" ]; then echo "A post for $tag already exists; update-existing is false, so it's left alone."; out post-url ""; exit 0; fi
  patch=$(jq -nc --arg t "$title" --arg b "$body" '{title:$t, body:$b}')
  code=$(curl -sS -o "$resp_file" -w '%{http_code}' -X PATCH "${auth[@]}" -H 'Content-Type: application/json' \
    --data "$patch" "$API/blogs/$blog/posts/$slug")
  resp=$(cat "$resp_file")
  [ "$code" = "200" ] || fail "Updating the existing post failed (HTTP $code): $resp"
  echo "Updated the existing post for $tag."
elif [ "$code" != "200" ] && [ "$code" != "201" ]; then
  fail "Publishing failed (HTTP $code): $resp"
fi
rm -f "$resp_file"

post_url=$(printf '%s' "$resp" | jq -r '.post_url // .post.url // empty')
if [ -n "$post_url" ]; then echo "Published: $post_url"; else echo "Saved (status: ${INPUT_STATUS:-published})."; fi
out post-url "$post_url"
