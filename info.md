# Blog Info

## GitHub Repository

- **Repo**: `ivemcfire/ivemcfire.github.io`
- **URL**: https://ivemcfire.github.io/
- **Git user**: ivemcfire
- **Branch**: `main` (deploys automatically via GitHub Pages)

## Upload Procedure

1. Make changes locally (new post HTML in `posts/`, images in `images/`, update `index.html`)
2. Stage files: `git add posts/new-post.html images/new-image.png index.html`
3. Commit: `git commit -m "Add new blog post - Title"`
4. Push: `git push origin main`
5. GitHub Pages picks up the push and deploys within ~1 minute. No build step.

## Blog Post Descriptions

| Post | File | Description |
|------|------|-------------|
| **Frigate NVR on Kubernetes** | `posts/frigate-nvr.html` | Deploying Frigate NVR on k3s to manage nine IP cameras with real-time object detection, face recognition on a 4K Reolink stream, Cloudflare Tunnel remote access, and nightly rsync backup to a netbook. Key lesson: downscaling from 4K preserves detail, upscaling from 360p does not. |
| **The Kubernetes Sidecar Pattern** | `posts/sidecar-pattern.html` | Adding structured logging and metrics to a FastAPI guitar app using Fluent Bit as a sidecar container, with shared emptyDir volume, three simultaneous outputs (Loki, Prometheus, stdout), and inotify-based tailing. |
| **Running Ollama Locally** | `posts/ollama-local-ai.html` | GPU-accelerated Mistral 7B via Ollama on a GTX 1050 Ti, exposed to k3s through WSL2 port forwarding, with Open WebUI providing a ChatGPT-like interface on the local network. |
| **K3s Phone Cluster** | `posts/k3s-phone-cluster.html` | Building a Kubernetes cluster from three OnePlus phones (postmarketOS, ARM64) and a Lenovo laptop, connected via USB ethernet tethering. 32 ARM cores, 27GB RAM, full Prometheus/Grafana monitoring. |
| **Guitar App Deploy** | `posts/guitar-app-deploy.html` | Containerizing a React + FastAPI audio processing app and deploying it to the k3s phone cluster with nginx reverse proxy and MetalLB LoadBalancer. |

## Directory Structure

```
ivemcfire.github.io/
├── index.html          # Homepage with post cards
├── posts/              # Individual blog post HTML files
├── images/             # Post images (use _small suffix for web)
├── CLAUDE.md           # Claude Code instructions
├── skills.md           # Blog creation skills reference
├── info.md             # This file
└── *.md                # Draft posts (not published)
```
