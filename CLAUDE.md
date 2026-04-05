# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a static HTML blog hosted on GitHub Pages at `ivemcfire.github.io`. The site documents homelab infrastructure experiments, including a k3s Kubernetes cluster built from old smartphones and a laptop.

## Architecture

- **No build system** - Pure HTML/CSS, no frameworks or static site generators
- **Single-page design** - `index.html` is the homepage with inline styles
- **Blog posts** - Individual HTML files in `posts/` directory
- **Images** - Stored in `images/` directory
- **Drafts** - Markdown files in root (e.g., `blog-frigate-nvr.md`) are unpublished drafts

## Deployment

Push to `main` branch deploys automatically via GitHub Pages. No build step required.

## Content Structure

Posts follow a consistent HTML template with:
- JetBrains Mono font for body text
- Instrument Serif for headings
- Dark theme (CSS variables in `:root`)
- Post cards on homepage link to individual HTML files in `posts/`

When creating new posts, copy the HTML structure from an existing post in `posts/` and update the content. Add a corresponding card entry to `index.html`.
