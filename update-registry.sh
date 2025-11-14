#!/bin/bash

# Auto-update plugin_registry.json from plugin repositories
# This script fetches plugin.yaml from each repository and updates the registry

set -e

REGISTRY_FILE="plugin_registry.json"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "🔍 Checking plugin repositories for updates..."

# Check if yq is installed (for YAML to JSON conversion)
if ! command -v yq &> /dev/null; then
    echo "❌ Error: yq is not installed"
    echo "💡 Install with: brew install yq"
    exit 1
fi

# Read the current registry
if [ ! -f "$REGISTRY_FILE" ]; then
    echo "❌ Error: $REGISTRY_FILE not found"
    exit 1
fi

# Extract repositories from the registry
repositories=$(jq -r '.plugins[].repository' "$REGISTRY_FILE")

# Create a new plugins array
echo '{"plugins": []}' > "$TEMP_DIR/new_registry.json"

# Process each repository
for repo in $repositories; do
    echo ""
    echo "📦 Processing: $repo"

    # Convert GitHub URL to API URL
    # https://github.com/user/repo -> https://api.github.com/repos/user/repo/contents/plugin.yaml
    repo_path=$(echo "$repo" | sed 's|https://github.com/||')
    api_url="https://api.github.com/repos/${repo_path}/contents/plugin.yaml"

    # Fetch plugin.yaml via GitHub API (bypasses CDN cache)
    response=$(curl -sf "$api_url")

    if [ $? -eq 0 ]; then
        echo "  ✅ Found plugin.yaml via GitHub API"

        # Extract and decode the base64 content
        echo "$response" | jq -r '.content' | base64 -d > "$TEMP_DIR/plugin.yaml"

        if [ $? -ne 0 ]; then
            echo "  ❌ Failed to decode content"
            continue
        fi
    else
        echo "  ⚠️  Could not fetch plugin.yaml, skipping..."
        continue
    fi

    # Convert YAML to JSON using yq
    yq -o=json '.' "$TEMP_DIR/plugin.yaml" > "$TEMP_DIR/plugin.json"

    if [ $? -eq 0 ]; then
        echo "  ✅ Converted YAML to JSON"

        # Add to new registry
        jq --slurpfile plugin "$TEMP_DIR/plugin.json" \
           '.plugins += $plugin' \
           "$TEMP_DIR/new_registry.json" > "$TEMP_DIR/tmp.json"
        mv "$TEMP_DIR/tmp.json" "$TEMP_DIR/new_registry.json"

        plugin_name=$(jq -r '.name' "$TEMP_DIR/plugin.json")
        plugin_version=$(jq -r '.version' "$TEMP_DIR/plugin.json")
        echo "  📝 Added $plugin_name v$plugin_version"
    else
        echo "  ❌ Failed to convert YAML"
        exit 1
    fi
done

# Pretty print and save the new registry
jq '.' "$TEMP_DIR/new_registry.json" > "$REGISTRY_FILE"

echo ""
echo "✅ Registry updated successfully!"
echo "📄 Updated: $REGISTRY_FILE"

# Show summary
plugin_count=$(jq '.plugins | length' "$REGISTRY_FILE")
echo "📊 Total plugins: $plugin_count"

# Show updated plugins
echo ""
echo "🔖 Plugins in registry:"
jq -r '.plugins[] | "  • \(.name) v\(.version)"' "$REGISTRY_FILE"
