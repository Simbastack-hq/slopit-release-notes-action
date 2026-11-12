# Publish release notes to SlopIt

[![changelog on SlopIt](https://slopit.io/badge/2wftdzzg.svg?label=changelog)](https://release-notes-demo.slopit.io/)

A GitHub Action that posts each release's notes to a [SlopIt](https://slopit.io) blog when the release is published. The notes go out exactly as you wrote them: no AI, no rewriting, no extra keys beyond the blog's own.

Every release gets its own page with its own URL, title and date, plus an entry in the blog's RSS feed, sitemap, `llms.txt` and a markdown copy. That's the changelog SEO checklist, done for you.

## Use it

1. Get a SlopIt blog and its API key. The free plan is fine, and you can let your coding agent sign up for you: "Start a SlopIt blog for this repo's release notes. Instructions: https://slopit.io/slopit.SKILL.md".
2. Add the key as a repository secret named `SLOPIT_API_KEY`.
3. Add `.github/workflows/release-notes.yml`:

```yaml
name: Release notes to SlopIt
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: Release tag to republish
        required: true
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: Simbastack-hq/slopit-release-notes-action@v0
        with:
          api-key: ${{ secrets.SLOPIT_API_KEY }}
          tag: ${{ inputs.tag }}
```

Publish a release, and the post appears on your blog a few seconds later. Fixed a typo in the notes afterwards? Run the workflow manually (Actions → Release notes to SlopIt → Run workflow) with the tag, and the same post is updated.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `api-key` | required | The blog's SlopIt API key. Keep it in a secret. |
| `status` | `published` | `draft` saves the post privately instead, so you can check it first. |
| `tags` | `release,changelog` | Comma-separated post tags. |
| `title` | release name, else `<repo> <tag>` | Post title. |
| `slug-prefix` | repo name | The post's slug is `<prefix>-<tag>`, e.g. `my-cli-v1-4-0`. |
| `include-prereleases` | `false` | Also post prereleases. |
| `update-existing` | `true` | When the release's post already exists (a manual run after you edited the notes), update its title and body instead of skipping. A re-run with unchanged notes returns the existing post and changes nothing. |
| `tag` | empty | For a manual run: the release tag to (re)publish. |
| `api-base` | `https://slopit.io/api` | Change it only for a self-hosted SlopIt. |

Outputs: `post-url`, the published post's URL, and `badge-markdown`, the README badge below.

## README badge

After each run, the job summary shows a badge for your README. It links to your changelog and shows the newest release and how long ago it went out, like the one at the top of this page:

```markdown
[![changelog on SlopIt](https://slopit.io/badge/{blog_id}.svg?label=changelog)](https://{your-blog}.slopit.io/)
```

Copy it from the summary (it has your blog's id and URL filled in) and paste it next to your other badges. Leave out `?label=changelog` and the badge says "blog".

## What it doesn't do

- It doesn't write anything. If you want a "what this release means" post, have your agent write it as a separate post.
- It skips draft releases. Prereleases are skipped too unless you turn them on.

## Live examples

- SlopIt's own releases post to https://changelog.slopit.io (workflow: [Simbastack-hq/SlopIt](https://github.com/Simbastack-hq/SlopIt/blob/main/.github/workflows/release-notes.yml)).
- This repo's releases post to https://release-notes-demo.slopit.io.

MIT licensed. Made by [SimbaStack](https://www.simbastack.com), the team behind SlopIt.
