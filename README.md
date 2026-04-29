# The Gap Has Weight

Static PSA website scaffold for a gender pay gap campaign. The site is designed as a low-noise, dark interface with clear movement through feeling, learning, and action.

## Project structure

- `public/`: deployable website root for Cloudflare Pages
- `public/index.html`: main campaign site
- `public/styles.css`: visual system and responsive layout
- `public/script.js`: audience-pathway switching
- `public/assets/`: placeholder visuals for the assessed artefacts
- `public/_headers`: Cloudflare Pages security headers
- `wrangler.toml`: Cloudflare Pages configuration
- `scripts/cloudflare_pages_deploy.rb`: direct-upload deployment helper

## Local preview

Run a simple local server from this folder:

```bash
cd public && ruby -run -e httpd . -p 4173 -b 127.0.0.1
```

Then open `http://127.0.0.1:4173`.

## Deploy to Cloudflare Pages

1. Create a new Pages project and connect this folder or repository.
2. Use the `None` framework preset.
3. Leave the build command empty.
4. Set the output directory to `public`.

CLI option:

```bash
wrangler pages deploy public --project-name the-gap-has-weight
```

Authenticate to Cloudflare through the dashboard or your local environment. Do not store API tokens or other secrets in this repository.

If Wrangler is unavailable, the repository also includes a Ruby helper for the Pages direct-upload API:

```bash
CLOUDFLARE_API_TOKEN=... ruby scripts/cloudflare_pages_deploy.rb
```

Optional environment variables:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_PROJECT_NAME` (defaults to `the-gap-has-weight`)
- `CLOUDFLARE_DEPLOY_DIR` (defaults to `public`)

## Content replacement checklist

- Replace the podcast placeholder with the final audio piece.
- Replace the infographic placeholder and insert three sourced data points.
- Replace the campaign image placeholder.
- Replace the physical artefact placeholder with final documentation.
- Review the current reference list and swap in any team-approved source changes.
- Review all copy for tone, geography, and audience-specific accuracy.