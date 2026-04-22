# Blog — Learning companion to the A365 Governed Pro-Code Agent Starter

This folder is a [Jekyll](https://jekyllrb.com/) site that GitHub Pages can
build directly. It re-frames the docs in [`../docs/`](../docs/) as a
blog-style learning series.

## Local preview

```pwsh
# 1. Install Ruby 3.x and Bundler (one-time).
# 2. Install gems.
cd blog
bundle install

# 3. Serve the site at http://127.0.0.1:4000
bundle exec jekyll serve
```

## Publishing on GitHub Pages

The repository ships with a workflow at
[`../.github/workflows/pages.yml`](../.github/workflows/pages.yml) that
builds this folder and publishes it to GitHub Pages on every push to the
default branch. To enable it:

1. Go to **Settings → Pages** in your GitHub repo.
2. Set **Source** to **GitHub Actions**.
3. Push to the default branch and wait for the `pages` workflow to finish.

If your repo is hosted at `https://github.com/<user>/<repo>`, the published
site will live at `https://<user>.github.io/<repo>/`. Update the `baseurl`
and `url` fields in [`_config.yml`](_config.yml) to match.

## Adding a new post

1. Drop a Markdown file in [`_posts/`](_posts/) named
   `YYYY-MM-DD-short-slug.md`.
2. Start with the YAML front matter used by the existing posts.
3. End with a **Go deeper** link to the canonical doc in `../docs/`.
