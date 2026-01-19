# Diagram Conversion Guide

## Overview
This directory contains Mermaid diagram source files (`.mmd`) extracted from the project documentation. These diagrams are used in the LaTeX report.

## Current Diagrams

1. **architecture_overview.mmd** - High-level system architecture showing frontend, backend, and external services
2. **er_diagram.mmd** - Entity-relationship diagram showing database schema

## Converting Diagrams to Images

### Prerequisites
Install mermaid-cli globally:
```bash
npm install -g @mermaid-js/mermaid-cli
```

### Conversion
Run the conversion script from the project root:
```bash
./convert_diagrams.sh
```

This will generate PNG images in the `images/` directory with the same base filename.

## Adding New Diagrams

1. Create a new `.mmd` file in this directory
2. Write your Mermaid diagram code
3. Run `./convert_diagrams.sh` to generate the image
4. Reference the image in your LaTeX file using `\includegraphics{images/your_diagram.png}`

## Mermaid Syntax

Mermaid supports various diagram types:
- Flowcharts: `graph TB` or `flowchart TD`
- Sequence diagrams: `sequenceDiagram`
- ER diagrams: `erDiagram`
- Class diagrams: `classDiagram`
- State diagrams: `stateDiagram-v2`

See https://mermaid.js.org/ for full documentation.
