# Skills Reference for Claude Code

## Creating a New Blog Post

1. **Draft** — Write content as a Markdown file in the repo root (e.g., `blog-topic-name.md`).
2. **Convert to HTML** — Copy the template from an existing post in `posts/` (e.g., `posts/sidecar-pattern.html`). The template includes:
   - CSS variables in `:root` (dark theme, accent `#ff6b35`)
   - Fonts: JetBrains Mono (body), Instrument Serif (headings)
   - Nav bar with `← Ivalin's Lab` linking to `/`
   - `<article>` wrapper with `<h1>`, subtitle `<em>`, then `<hr />` sections
   - Code blocks use `<div class="codehilite"><pre><span></span><code>...</code></pre></div>`
   - Tables use standard HTML `<table>` with `<thead>` and `<tbody>`
   - Images use `<img src="../images/filename.png" alt="..." />` with optional `<p class="photo-caption">` below
   - Footer, back-to-top button, and copy-button JS at the bottom
3. **Add card to index.html** — Insert a new `<a href="posts/filename.html" class="post">` block at the top of the posts list in `index.html`. Include `post-meta` (month/year + read time), `<h2>` title, `<p>` summary, and `.tags` spans.
4. **Images** — Place in `images/` directory. Reference from posts as `../images/filename.png`.
5. **Commit and push** — Push to `main` branch; GitHub Pages deploys automatically.

## Blog Style Guidelines

- **Tone**: Technical, first-person, conversational but precise. Document what was tried, what failed, and why the solution works.
- **Structure**: Problem → Architecture/Setup → Deep-dive sections → Things That Went Wrong → The Payoff → Cluster Context
- **"Things That Went Wrong" section** is a signature element — always include it with real debugging stories.
- **"Cluster Context" section** at the end links back to the k3s phone cluster and shows the node table.
- **Previous posts links** at the bottom of each post.
- **No emojis** in posts.
- **Code snippets** should be real commands/configs from the actual setup.
- **Tables** for specs, comparisons, and structured data.

## Post Template Quick Reference

```html
<!doctype html>
<html lang="en">
  <head>
    <!-- charset, viewport, title with " — Ivalin's Lab" suffix -->
    <!-- Google Fonts link for JetBrains Mono + Instrument Serif -->
    <!-- Full <style> block copied from existing post -->
  </head>
  <body>
    <div class="grain"></div>
    <nav><a href="/">← Ivalin's Lab</a></nav>
    <article>
      <h1>Title Here</h1>
      <p><em>Subtitle/summary here.</em></p>
      <hr />
      <!-- Sections with <h2>, <h3>, <p>, tables, code blocks, images -->
      <hr />
      <p>Previous posts: <a href="...">...</a> · ...</p>
    </article>
    <footer>Built with bare HTML and deployed on GitHub Pages.</footer>
    <!-- back-to-top button + JS -->
  </body>
</html>
```
