# ollama

Local Ollama stack with Open WebUI and SearXNG. Designed for use with opencode.  
  
## Directory Structure  
  
```
ollama/
├── data/
│   ├── models/       # Ollama model storage (blobs, manifests, keys)
│   │   └── imports/ # Drop local .gguf files here for import
│   ├── obsidian/
│   │   └── vault/   # OKF-format knowledge bank, read/write by models
│   ├── openwebui/    # User accounts, chat history
│   ├── prompts/      # System prompt files
│   └── searxng/      # SearXNG configuration
│       └── settings.yml.template
├── logs/             # Application logs
├── scripts/
│   ├── coldstart.sh  # Bring up all containers from scratch
│   ├── stop.sh       # Stop container, optionally remove them
│   ├── maint.sh      # Maintenance tools (permissions, model purge, webui)
│   └── prompts.sh    # Prompt management
├── secrets           # Environment variables (git-ignored)
├── secrets.template  # Template - copy to secrets and fill in
├── README.md
└── LICENSE
```
  
## Prerequisites  
  
- Podman (or Docker with podman alias)  
- Internet connection (for pulling images)  
  
## Setup  
  
1. Copy the secrets.example file to secrets in the project root and fill in the values:  
  
```bash
cp secrets.template secrets
$EDITOR secrets
```

Values ('SEARXNG_SECRET_KEY', 'WEBUI_ADMIN_EMAIL', 'WEBUI_ADMIN_PASSWORD', 'WEBUI_SECRET_KEY') must be real, literal values; 'coldstart.sh' validates this and refuses to start in any are blank.
  
2. Run the cold-start script:  
  
```bash
./scripts/coldstart.sh
```
  
This creates the 'ollama-net' podman network, starts all three containers, and prompts you to pull a model.  
  
## Stopping / Rebuilding
  
```bash
./scripts/stop.sh
```
  
Stops all containers. You'll be asked whether to remove them as well.  
Removal is safe: models, chat history, and web-search config all live under 'data/', outside of the containers, so another './scripts/coldstart.sh' rebuilds the stack with everything intact.  
  
## Services  
  
| Service | Container | Port | Purpose |  
|---------|-----------|------|---------|  
| Ollama | ollama | 11434 | LLM inference API |  
| Open WebUI | openwebui | 3000 | Browser-based chat interface |  
| SearXNG | searxng | 8888 | Web search for RAG |  
  
## Model Selection  
  
'coldstart.sh' first shows models already installed, then loops a menu until you choose to skip. This way you can pull or import several or no models in one run:  
  
| # | Option | Description |
|---|--------|-------------|
| 0 | Skip | Continue without pulling anything new |
| 1 | HuggingFace | Pull any GGUF model via `hf.co/org/repo:quant` - browse [huggingface.co/models](https://huggingface.co/models?apps=ollama&sort=trending), use "Use this model" → Ollama on a model page to get the exact reference |
| 2 | Ollama library | Type any model name from [ollama.com/library](https://ollama.com/library) |
| 3 | Local file | Import a `.gguf` you already have - drop it in `data/models/imports/` first, then select it by filename and give it a model name |
  
A bad model name or failed pull/import logs an error and returns to the menu rather than aborting the whole coldstart.  

## Maintenance  

```bash
./scripts/maint.sh
```
  
A menu-driven tool for recurring maintenance tasks:  
  
| # | Tool | Purpose |
|---|------|---------|
| 1 | Fix permissions | Reclaims host ownership of container-written data directories (see Known Quirks below) |
| 2 | Purge models | Lists installed models and removes a chosen one via `ollama rm`, which safely handles blobs shared between models |
| 3 | Reset WebUI | Three separate options - full wipe (including admin account), chat history only, or RAG/vector cache only |
  
## Usage with opencode  
  
Configure opencode to use the local Ollama instance. The API key is stored in your `secrets` file:  
  
```json  
{
  "provider": {
    "ollama": {
      "apiKey": "${OPENCODE_OLLAMA_API_KEY}",
      "models": {
        "llama3.1:8b": {
          "maxTokens": 8192,
          "contextWindow": 128000
        }
      }
    }
  }
}
```
  
## Web Search (RAG)  
  
Open WebUI is pre-configured to use SearXNG for web search. To confirm:  
  
1. Open Open WebUI at `http://localhost:3000`
2. Go to **Admin Panel** → **Settings** → **Web Search**
3. Confirm **Enable Web Search** is on and engine is set to 'searxng'
4. Confirm **Searxng Query URL** to `http://searxng:8080/search?q=<query>`  
  
Note: not all models support tool-calling, which some Web Search intergrations rely on. If a model reports something like "does not support tools", try a model known to support function calling (e.g. 'qwen2.5', 'llama3.1') instead.  
  
## Knowledge Bank (OKF)  
  
'data/obsidian/vault/' is a read-write knowledge bank in [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing/). Plain mardown files with a YAML frontmatter, one concept per file. It's bootstrapped with a seed 'index.md' on first cold start. The directory can also be opened directly in Obsidian, since OKF is fully compatible with Obsidian's vault format.  
  
## System Prompts  
  
System prompts are stored in `data/prompts/` as Markdown files with YAML frontmatter. Use the management script to work with them:  
  
```bash
# List all prompts
./scripts/prompts.sh list

# Display a prompt (copy/paste into Open WebUI)
./scripts/prompts.sh show code-assistant

# Create a new prompt interactively
./scripts/prompts.sh create

# Delete a prompt
./scripts/prompts.sh delete creative-writer
```
  
### Using prompts in Open WebUI  
  
1. Run `./scripts/prompts.sh show <name>` to display the prompt  
2. Copy the output  
3. Open Open WebUI → **Admin Panel** → **Settings** → **System Prompt**  
4. Paste and save  
  
### Prompt file format  
  
```markdown
---
name: Code Assistant
description: Specialized in code review and refactoring
tags: [code, programming]
---

You are a senior software engineer...
```
  
The YAML frontmatter (`name`, `description`, `tags`) is used for display purposes only. The actual system prompt is everything after the closing `---`.  
  
### Included prompts  
  
| File | Name | Purpose |  
|------|------|---------|  
| `code-assistant.md` | Code Assistant | Code review, refactoring, best practices |  
| `creative-writer.md` | Creative Writer | Storytelling, content creation |  
| `technical-docs.md` | Technical Writer | Documentation, guides, explanations |  
  
## Known Quirks

**Rootless podman UID mapping (SearXNG only):** SearXNG's image runs as a fixed non-root user (UID 977) rather than root, so its container-written files ('data/searxng/settings.yml') can end up owned by a mapped UID that isn't directly writable from the host. Ollama and Open WebUI don't have this issue - both run as root internally, and rootless podman already maps root-owner files back to your host user correctly.  
  
If you need to hand-edit a file under 'data/' and get a permission error, run:
```bash
./scripts/maint.sh
```
and choose option 1 (Fix permission). Do not use 'podman unshare chown -R $(id-u):$(id -g)'. That's tevaluated outside the namespace and maps the wrong UID.
  
## Logs  
  
Application logs are stored in `logs/ollama.log`.  

## License  

MIT - see [LICENSE](LICENSE).  
  
