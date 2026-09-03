#!/bin/bash
# prompts.sh - manage system prompts
set -euo pipefail

PROMPTS_DIR="$(dirname "$0")/../data/prompts"

usage() {
    cat << 'EOF'
Usage: prompts.sh <command> [args]

Commands:
  list              List all available prompts
  show <name>       Display a prompt's full content
  create            Create a new prompt interactively
  delete <name>     Delete a prompt file
  help              Show this help message
EOF
}

list_prompts() {
    echo ""
    echo "Available prompts:"
    echo ""

    local count=0
    for f in "$PROMPTS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        count=$((count + 1))

        local name desc
        name=$(grep '^name:' "$f" | head -1 | sed 's/^name: *//')
        desc=$(grep '^description:' "$f" | head -1 | sed 's/^description: *//')
        local base
        base=$(basename "$f" .md)

        printf "  %-20s %s\n" "$base" "$name - $desc"
    done

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    fi

    echo ""
}

show_prompt() {
    local name="$1"
    local file="$PROMPTS_DIR/${name}.md"

    if [[ ! -f "$file" ]]; then
        echo "Error: prompt '$name' not found"
        exit 1
    fi

    # Print everything after the opening --- and closing --- of frontmatter
    sed -n '/^---$/,/^---$/d; p' "$file"
}

create_prompt() {
    echo ""
    echo "=== Create new prompt ==="
    echo ""

    read -rp "Filename (no extension): " filename
    if [[ -z "$filename" ]]; then
        echo "Error: filename required"
        exit 1
    fi

    local file="$PROMPTS_DIR/${filename}.md"
    if [[ -f "$file" ]]; then
        echo "Error: $filename.md already exists"
        exit 1
    fi

    read -rp "Display name: " display_name
    read -rp "Description: " description
    read -rp "Tags (comma-separated): " tags

    # Convert comma-separated tags to YAML list
    local yaml_tags=""
    IFS=',' read -ra tag_array <<< "$tags"
    for tag in "${tag_array[@]}"; do
        tag=$(echo "$tag" | xargs)  # trim whitespace
        yaml_tags="${yaml_tags}\n  - ${tag}"
    done

    echo ""
    echo "Enter your system prompt (Ctrl+D when done):"
    echo "---"
    local content
    content=$(cat)

    {
        echo "---"
        echo "name: ${display_name}"
        echo "description: ${description}"
        echo -e "tags:${yaml_tags}"
        echo "---"
        echo ""
        echo "$content"
    } > "$file"

    echo ""
    echo "Created: $file"
}

delete_prompt() {
    local name="$1"
    local file="$PROMPTS_DIR/${name}.md"

    if [[ ! -f "$file" ]]; then
        echo "Error: prompt '$name' not found"
        exit 1
    fi

    read -rp "Delete '$name'? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm "$file"
        echo "Deleted: $name"
    else
        echo "Cancelled"
    fi
}

# --- Main ---
[[ $# -lt 1 ]] && { usage; exit 1; }

case "$1" in
    list)   list_prompts ;;
    show)
        [[ $# -lt 2 ]] && { echo "Error: prompt name required"; exit 1; }
        show_prompt "$2"
        ;;
    create) create_prompt ;;
    delete)
        [[ $# -lt 2 ]] && { echo "Error: prompt name required"; exit 1; }
        delete_prompt "$2"
        ;;
    help|*) usage ;;
esac
