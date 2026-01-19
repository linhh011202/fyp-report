#!/bin/bash

# Diagram conversion script using mermaid-cli
# This script converts all .mmd files in the diagrams/ folder to PNG images

echo "Converting Mermaid diagrams to images..."

# Check if mmdc is installed
if ! command -v mmdc &> /dev/null; then
    echo "Error: mermaid-cli (mmdc) is not installed."
    echo "Please install it with: npm install -g @mermaid-js/mermaid-cli"
    exit 1
fi

# Create images directory if it doesn't exist
mkdir -p images

# Convert each .mmd file to PNG
for file in diagrams/*.mmd; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .mmd)
        echo "Converting $filename..."
        mmdc -i "$file" -o "images/${filename}.png" -w 1200 -b transparent
    fi
done

echo "Conversion complete! Images saved to images/"
