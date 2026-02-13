import os
import xml.etree.ElementTree as ET
from pathlib import Path

# Configuration
svg_dir = Path("docs/images")
output_file = "docs/images/combined_diagrams.svg"
spacing = 50  # Space between diagrams
columns = 3  # Number of columns in grid

# Get all SVG files
svg_files = sorted(svg_dir.glob("*.svg"))

if not svg_files:
    print("No SVG files found!")
    exit(1)

# Parse all SVGs and collect their content
diagrams = []
max_width = 0
total_height = 0

for svg_file in svg_files:
    tree = ET.parse(svg_file)
    root = tree.getroot()
    
    # Get dimensions
    width = float(root.get('width', 800))
    height = float(root.get('height', 600))
    viewBox = root.get('viewBox', f"0 0 {width} {height}")
    
    # Extract all children (the actual diagram content)
    content = list(root)
    
    diagrams.append({
        'name': svg_file.stem,
        'width': width,
        'height': height,
        'viewBox': viewBox,
        'content': content,
        'root': root
    })
    
    max_width = max(max_width, width)
    total_height += height + spacing

# Calculate grid layout
rows = (len(diagrams) + columns - 1) // columns
grid_width = columns * max_width + (columns - 1) * spacing
grid_height = rows * max(d['height'] for d in diagrams) + (rows - 1) * spacing

# Create combined SVG
combined = ET.Element('svg', {
    'width': str(grid_width),
    'height': str(grid_height),
    'viewBox': f"0 0 {grid_width} {grid_height}",
    'xmlns': 'http://www.w3.org/2000/svg'
})

# Add background
ET.SubElement(combined, 'rect', {
    'x': '0', 'y': '0',
    'width': str(grid_width),
    'height': str(grid_height),
    'fill': 'white'
})

# Place diagrams in grid
for idx, diagram in enumerate(diagrams):
    row = idx // columns
    col = idx % columns
    
    x = col * (max_width + spacing)
    y = row * (max(d['height'] for d in diagrams) + spacing)
    
    # Create group for this diagram
    g = ET.SubElement(combined, 'g', {
        'transform': f'translate({x}, {y})'
    })
    
    # Add title
    title = ET.SubElement(g, 'text', {
        'x': str(diagram['width'] / 2),
        'y': '20',
        'text-anchor': 'middle',
        'font-family': 'Arial, Helvetica, sans-serif',
        'font-size': '16',
        'font-weight': 'bold',
        'fill': '#2c3e50'
    })
    title.text = diagram['name']
    
    # Add diagram content
    diagram_group = ET.SubElement(g, 'g')
    for elem in diagram['content']:
        diagram_group.append(elem)

# Write output
tree = ET.ElementTree(combined)
ET.indent(tree, space="  ")
tree.write(output_file, encoding='utf-8', xml_declaration=True)

print(f"Combined {len(svg_files)} SVGs into {output_file}")
print(f"Grid: {columns} columns × {rows} rows")
print(f"Dimensions: {grid_width} × {grid_height}")