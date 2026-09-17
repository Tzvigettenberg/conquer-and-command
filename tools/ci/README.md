# Release workflow (parked)

`release.yml` builds the Windows zip on GitHub's runners whenever a `v*` tag is pushed and attaches
it to the release, so a build does not depend on anyone's PC.

It lives here rather than in `.github/workflows/` because pushing a workflow file needs a token with
the **Workflows: Read and write** permission, and ours only has Contents. Add that permission to the
token (GitHub -> Settings -> Developer settings -> Fine-grained tokens -> edit), then:

```
mkdir -p .github/workflows && git mv tools/ci/release.yml .github/workflows/release.yml
git commit -m "Enable the release workflow" && python3 tools/release.py
```

Until then the download on the website is published straight from `build/` by
`tools/publish_site.py`, which needs no extra permission.
