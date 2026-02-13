#!/usr/bin/env python3
"""
Verilog to SVG Symbol Generator
Creates a basic block symbol with inputs on left, outputs on right.
"""

import re
import sys
import argparse
from pathlib import Path

def parse_verilog_module(verilog_code):
    """Extract module name, inputs, and outputs from Verilog code."""
    # Remove comments
    verilog_code = re.sub(r'//.*$', '', verilog_code, flags=re.MULTILINE)
    verilog_code = re.sub(r'/\*.*?\*/', '', verilog_code, flags=re.DOTALL)
    
    # Find module name
    module_match = re.search(r'module\s+(\w+)', verilog_code)
    if not module_match:
        raise ValueError("No module declaration found")
    module_name = module_match.group(1)
    
    inputs = []
    outputs = []
    
    # Method 1: Find all input/output declarations in the port list (ANSI style)
    # This handles your specific format: "input wire [7:0] CHEN_sync," etc.
    port_section = re.search(r'module\s+\w+\s*\((.*?)\)\s*;', verilog_code, re.DOTALL)
    if port_section:
        port_text = port_section.group(1)
        
        # Split by commas that are not inside parentheses
        ports = []
        current_port = ""
        paren_count = 0
        
        for char in port_text:
            current_port += char
            if char == '(':
                paren_count += 1
            elif char == ')':
                paren_count -= 1
            elif char == ',' and paren_count == 0:
                ports.append(current_port[:-1].strip())
                current_port = ""
        if current_port.strip():
            ports.append(current_port.strip())
        
        # Process each port declaration
        for port in ports:
            port = port.strip()
            
            # Skip if empty
            if not port:
                continue
            
            # Check for input
            if re.match(r'^input\b', port, re.IGNORECASE):
                # Extract the port name - it's typically the last word before any comment
                # Remove the 'input' keyword and any types/ranges
                port_clean = re.sub(r'^input\s+', '', port, flags=re.IGNORECASE)
                port_clean = re.sub(r'\b(reg|wire|logic)\b', '', port_clean, flags=re.IGNORECASE)
                port_clean = re.sub(r'\[[^\]]*\]', '', port_clean)  # Remove bus ranges
                
                # Split by whitespace and take the last word before any comment
                parts = port_clean.split()
                if parts:
                    # Handle case where there might be a comment after //
                    name_part = parts[-1].split('//')[0].strip()
                    if name_part:
                        inputs.append(name_part)
            
            # Check for output
            elif re.match(r'^output\b', port, re.IGNORECASE):
                # Extract the port name
                port_clean = re.sub(r'^output\s+', '', port, flags=re.IGNORECASE)
                port_clean = re.sub(r'\b(reg|wire|logic)\b', '', port_clean, flags=re.IGNORECASE)
                port_clean = re.sub(r'\[[^\]]*\]', '', port_clean)  # Remove bus ranges
                
                # Split by whitespace and take the last word before any comment
                parts = port_clean.split()
                if parts:
                    name_part = parts[-1].split('//')[0].strip()
                    if name_part:
                        outputs.append(name_part)
    
    # Method 2: If still no outputs, look for standalone declarations
    if not outputs:
        # Find all output declarations anywhere in the file
        output_decls = re.findall(r'output\s+(?:wire|reg|logic)?\s*(?:\[[^\]]*\])?\s*(\w+)', 
                                 verilog_code, re.IGNORECASE)
        outputs.extend(output_decls)
    
    # Method 3: If still no inputs, look for standalone input declarations
    if not inputs:
        input_decls = re.findall(r'input\s+(?:wire|reg|logic)?\s*(?:\[[^\]]*\])?\s*(\w+)', 
                                verilog_code, re.IGNORECASE)
        inputs.extend(input_decls)
    
    # Remove duplicates while preserving order
    inputs = list(dict.fromkeys(inputs))
    outputs = list(dict.fromkeys(outputs))
    
    return module_name, inputs, outputs

def generate_svg(module_name, inputs, outputs):
    """Generate SVG symbol for the module with proper sizing."""
    
    # Configuration
    BLOCK_WIDTH = 350
    BLOCK_MIN_HEIGHT = 200
    PORT_SPACING = 35
    PORT_PADDING = 30
    LEFT_MARGIN = 200
    RIGHT_MARGIN = 200
    TOP_MARGIN = 100
    BOTTOM_MARGIN = 80
    
    # Calculate required height based on number of ports
    num_ports = max(len(inputs), len(outputs), 2)
    ports_height = num_ports * PORT_SPACING + PORT_PADDING
    block_height = max(BLOCK_MIN_HEIGHT, ports_height)
    
    # Calculate total SVG dimensions
    svg_width = BLOCK_WIDTH + LEFT_MARGIN + RIGHT_MARGIN
    svg_height = block_height + TOP_MARGIN + BOTTOM_MARGIN
    
    # Block position
    block_x = LEFT_MARGIN
    block_y = TOP_MARGIN + (ports_height - block_height) / 2
    
    # Start building SVG
    svg = []
    svg.append('<?xml version="1.0" encoding="UTF-8"?>')
    svg.append(f'<svg width="{svg_width}" height="{svg_height}" '
               f'viewBox="0 0 {svg_width} {svg_height}" '
               f'xmlns="http://www.w3.org/2000/svg">')
    
    # White background
    svg.append(f'  <rect x="0" y="0" width="{svg_width}" height="{svg_height}" fill="white"/>')
    
    # Main block
    svg.append(f'  <rect x="{block_x}" y="{block_y}" width="{BLOCK_WIDTH}" height="{block_height}" '
               f'fill="#f8f9fa" stroke="#2c3e50" stroke-width="2.5" rx="10" ry="10"/>')
    
    # Module name with background for better visibility
    svg.append(f'  <rect x="{block_x + BLOCK_WIDTH/2 - 120}" y="{block_y - 40}" '
               f'width="240" height="30" fill="white" stroke="none"/>')
    svg.append(f'  <text x="{block_x + BLOCK_WIDTH/2}" y="{block_y - 18}" '
               f'text-anchor="middle" font-family="Arial, Helvetica, sans-serif" '
               f'font-size="20" font-weight="bold" fill="#2c3e50">{module_name}</text>')
    
    # Input ports (left side)
    if inputs:
        input_spacing = block_height / (len(inputs) + 1)
        for i, port in enumerate(inputs, 1):
            port_y = block_y + i * input_spacing
            
            # Connection line
            svg.append(f'  <line x1="{block_x - 25}" y1="{port_y}" '
                       f'x2="{block_x}" y2="{port_y}" stroke="#34495e" stroke-width="1.5"/>')
            
            # Port name with white background for readability
            svg.append(f'  <rect x="{block_x - 190}" y="{port_y - 10}" '
                       f'width="160" height="20" fill="white" stroke="none"/>')
            svg.append(f'  <text x="{block_x - 30}" y="{port_y + 5}" '
                       f'text-anchor="end" font-family="Arial, Helvetica, sans-serif" '
                       f'font-size="13" fill="#2c3e50">{port}</text>')
            
            # Port dot
            svg.append(f'  <circle cx="{block_x}" cy="{port_y}" r="3.5" fill="#2c3e50"/>')
    
    # Output ports (right side)
    if outputs:
        output_spacing = block_height / (len(outputs) + 1)
        for i, port in enumerate(outputs, 1):
            port_y = block_y + i * output_spacing
            
            # Connection line
            svg.append(f'  <line x1="{block_x + BLOCK_WIDTH}" y1="{port_y}" '
                       f'x2="{block_x + BLOCK_WIDTH + 25}" y2="{port_y}" stroke="#34495e" stroke-width="1.5"/>')
            
            # Port name with white background for readability
            svg.append(f'  <rect x="{block_x + BLOCK_WIDTH + 30}" y="{port_y - 10}" '
                       f'width="160" height="20" fill="white" stroke="none"/>')
            svg.append(f'  <text x="{block_x + BLOCK_WIDTH + 35}" y="{port_y + 5}" '
                       f'text-anchor="start" font-family="Arial, Helvetica, sans-serif" '
                       f'font-size="13" fill="#2c3e50">{port}</text>')
            
            # Port dot
            svg.append(f'  <circle cx="{block_x + BLOCK_WIDTH}" cy="{port_y}" r="3.5" fill="#2c3e50"/>')
    
    # Add I/O count summary
    svg.append(f'  <text x="{svg_width/2}" y="{svg_height - 20}" '
               f'text-anchor="middle" font-family="Arial, Helvetica, sans-serif" '
               f'font-size="11" fill="#7f8c8d">Inputs: {len(inputs)}  |  Outputs: {len(outputs)}</text>')
    
    svg.append('</svg>')
    
    return '\n'.join(svg)

def verilog_to_svg(input_file, output_file=None, debug=False):
    """Convert Verilog file to SVG symbol."""
    
    # Read Verilog file
    try:
        with open(input_file, 'r') as f:
            verilog_code = f.read()
    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found")
        return False
    except Exception as e:
        print(f"Error reading file: {e}")
        return False
    
    # Parse module
    try:
        module_name, inputs, outputs = parse_verilog_module(verilog_code)
    except ValueError as e:
        print(f"Error parsing Verilog: {e}")
        return False
    
    if not inputs and not outputs:
        print("Warning: No inputs or outputs found")
    
    print("=" * 70)
    print(f"📦 Module: {module_name}")
    print(f"📥 Inputs ({len(inputs)}):")
    for i, inp in enumerate(inputs, 1):
        print(f"    {i:2d}. {inp}")
    print(f"📤 Outputs ({len(outputs)}):")
    for i, out in enumerate(outputs, 1):
        print(f"    {i:2d}. {out}")
    print("=" * 70)
    
    # Generate SVG
    svg_content = generate_svg(module_name, inputs, outputs)
    
    # Determine output filename
    if not output_file:
        output_file = Path(input_file).stem + '_symbol.svg'
    
    # Write SVG file
    try:
        with open(output_file, 'w') as f:
            f.write(svg_content)
        print(f"✅ SVG symbol saved to: {output_file}")
        
        # Debug info
        if debug:
            debug_file = Path(input_file).stem + '_debug.txt'
            with open(debug_file, 'w') as f:
                f.write(f"Module: {module_name}\n")
                f.write(f"Inputs ({len(inputs)}): {inputs}\n")
                f.write(f"Outputs ({len(outputs)}): {outputs}\n")
                f.write("\nOriginal Verilog:\n")
                f.write(verilog_code)
            print(f"🔍 Debug info saved to: {debug_file}")
        
        return True
    except Exception as e:
        print(f"Error writing SVG file: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Generate SVG block symbol from Verilog module',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('input', help='Input Verilog file')
    parser.add_argument('-o', '--output', help='Output SVG file (default: input_symbol.svg)')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    
    args = parser.parse_args()
    
    if not verilog_to_svg(args.input, args.output, args.debug):
        sys.exit(1)

if __name__ == '__main__':
    main()