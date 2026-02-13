#!/usr/bin/env python3
"""
Verilog to SVG Symbol Generator
Creates a basic block symbol with inputs on left, outputs on right.
Handles both ANSI and non-ANSI style port declarations.
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
    inouts = []
    
    # Extract the port list from module declaration
    # Handle both regular modules and parameterized modules:
    # module NAME (ports);
    # module NAME #(parameters) (ports);
    port_list_match = re.search(
        r'module\s+\w+\s*(?:#\s*\([^)]*\)\s*)?\((.*?)\)\s*;', 
        verilog_code, 
        re.DOTALL
    )
    if not port_list_match:
        raise ValueError("No port list found in module declaration")
    
    port_list_text = port_list_match.group(1)
    
    # Split port list by commas (handling nested brackets/parentheses)
    port_names = []
    current_port = ""
    bracket_depth = 0
    paren_depth = 0
    
    for char in port_list_text:
        if char == '[':
            bracket_depth += 1
        elif char == ']':
            bracket_depth -= 1
        elif char == '(':
            paren_depth += 1
        elif char == ')':
            paren_depth -= 1
        elif char == ',' and bracket_depth == 0 and paren_depth == 0:
            port_names.append(current_port.strip())
            current_port = ""
            continue
        current_port += char
    
    if current_port.strip():
        port_names.append(current_port.strip())
    
    # Method 1: Try ANSI-style (declarations in port list)
    ansi_inputs = []
    ansi_outputs = []
    ansi_inouts = []
    
    for port in port_names:
        port = port.strip()
        if not port:
            continue
        
        # Check for input in ANSI style
        if re.match(r'^input\b', port, re.IGNORECASE):
            # Extract the port name
            port_clean = re.sub(r'^input\s+', '', port, flags=re.IGNORECASE)
            port_clean = re.sub(r'\b(reg|wire|logic|signed|unsigned)\b', '', port_clean, flags=re.IGNORECASE)
            port_clean = re.sub(r'\[[^\]]*\]', '', port_clean)  # Remove bus ranges
            parts = port_clean.split()
            if parts:
                name = parts[-1].split('//')[0].strip()
                if name:
                    ansi_inputs.append(name)
        
        # Check for output in ANSI style
        elif re.match(r'^output\b', port, re.IGNORECASE):
            port_clean = re.sub(r'^output\s+', '', port, flags=re.IGNORECASE)
            port_clean = re.sub(r'\b(reg|wire|logic|signed|unsigned)\b', '', port_clean, flags=re.IGNORECASE)
            port_clean = re.sub(r'\[[^\]]*\]', '', port_clean)
            parts = port_clean.split()
            if parts:
                name = parts[-1].split('//')[0].strip()
                if name:
                    ansi_outputs.append(name)
        
        # Check for inout in ANSI style
        elif re.match(r'^inout\b', port, re.IGNORECASE):
            port_clean = re.sub(r'^inout\s+', '', port, flags=re.IGNORECASE)
            port_clean = re.sub(r'\b(reg|wire|logic|signed|unsigned)\b', '', port_clean, flags=re.IGNORECASE)
            port_clean = re.sub(r'\[[^\]]*\]', '', port_clean)
            parts = port_clean.split()
            if parts:
                name = parts[-1].split('//')[0].strip()
                if name:
                    ansi_inouts.append(name)
    
    # Method 2: Non-ANSI style - get port names from list, then find declarations inside module
    # Extract just the port names from the port list (for non-ANSI style)
    simple_port_names = []
    for port in port_names:
        port = port.strip()
        if not port:
            continue
        
        # If it doesn't start with input/output/inout, it's just a name (non-ANSI)
        if not re.match(r'^(input|output|inout)\b', port, re.IGNORECASE):
            # Clean up the name - remove any attributes, ranges, etc.
            port_clean = re.sub(r'\[[^\]]*\]', '', port)  # Remove ranges
            port_clean = re.sub(r'\(.*?\)', '', port_clean)  # Remove attributes
            parts = port_clean.split()
            if parts:
                name = parts[-1].split('//')[0].strip()
                if name:
                    simple_port_names.append(name)
    
    # Now find the input/output declarations inside the module body
    # Extract the module body (everything after the port list semicolon until endmodule)
    # Handle parameterized modules: module NAME #(...) (...);
    module_body_match = re.search(
        r'module\s+\w+\s*(?:#\s*\([^)]*\)\s*)?\(.*?\)\s*;(.*?)endmodule', 
        verilog_code, 
        re.DOTALL
    )
    
    non_ansi_inputs = []
    non_ansi_outputs = []
    non_ansi_inouts = []
    
    if module_body_match and simple_port_names:
        module_body = module_body_match.group(1)
        
        # Find all input declarations
        # Handles various formats: "input X;", "input [7:0] X;", "input wire [7:0] X;"
        # Also handles comma-separated: "input A, B, C;"
        input_matches = re.finditer(
            r'^\s*input\s+(.+?);',
            module_body, re.MULTILINE
        )
        for match in input_matches:
            # Extract all port names from this declaration (might be comma-separated)
            declaration = match.group(1)
            
            # Remove type keywords and ranges to get the name list
            # Handle ranges with or without spaces: "[7:0]X" or "[7:0] X"
            declaration = re.sub(r'\b(wire|reg|logic|signed|unsigned)\b', '', declaration)
            
            # Extract names - split by comma first
            name_parts = declaration.split(',')
            
            for name_part in name_parts:
                name_part = name_part.strip()
                # Remove any ranges (handling both "[7:0] name" and "[7:0]name")
                name_part = re.sub(r'\[[^\]]*\]\s*', '', name_part)
                # Remove any remaining whitespace
                name_part = name_part.strip()
                # Get the identifier (should be what's left)
                # Handle cases with comments
                name_part = name_part.split('//')[0].strip()
                # Extract just the identifier word
                match_id = re.match(r'(\w+)', name_part)
                if match_id:
                    name = match_id.group(1)
                    if name in simple_port_names:
                        non_ansi_inputs.append(name)
        
        # Find all output declarations
        # Need to handle attributes like (* keep = 1 *) before output keyword
        output_matches = re.finditer(
            r'(?:\(\*[^)]*\*\)\s*)?output\s+(.+?);',
            module_body, re.MULTILINE
        )
        for match in output_matches:
            declaration = match.group(1)
            
            # Remove type keywords and ranges
            declaration = re.sub(r'\b(wire|reg|logic|signed|unsigned)\b', '', declaration)
            
            # Remove inline comments like /* cadence preserve_sequential */
            declaration = re.sub(r'/\*.*?\*/', '', declaration)
            
            # Split by comma
            name_parts = declaration.split(',')
            
            for name_part in name_parts:
                name_part = name_part.strip()
                # Remove ranges
                name_part = re.sub(r'\[[^\]]*\]\s*', '', name_part)
                name_part = name_part.strip()
                # Remove comments
                name_part = name_part.split('//')[0].strip()
                # Extract identifier
                match_id = re.match(r'(\w+)', name_part)
                if match_id:
                    name = match_id.group(1)
                    if name in simple_port_names:
                        non_ansi_outputs.append(name)
        
        # Find all inout declarations
        inout_matches = re.finditer(
            r'(?:\(\*[^)]*\*\)\s*)?inout\s+(.+?);',
            module_body, re.MULTILINE
        )
        for match in inout_matches:
            declaration = match.group(1)
            declaration = re.sub(r'\b(wire|reg|logic|signed|unsigned)\b', '', declaration)
            declaration = re.sub(r'/\*.*?\*/', '', declaration)
            name_parts = declaration.split(',')
            
            for name_part in name_parts:
                name_part = name_part.strip()
                name_part = re.sub(r'\[[^\]]*\]\s*', '', name_part)
                name_part = name_part.strip()
                name_part = name_part.split('//')[0].strip()
                match_id = re.match(r'(\w+)', name_part)
                if match_id:
                    name = match_id.group(1)
                    if name in simple_port_names:
                        non_ansi_inouts.append(name)
    
    # Combine ANSI and non-ANSI results (prefer non-ANSI if both exist, as it's more complete)
    if non_ansi_inputs or non_ansi_outputs:
        inputs = non_ansi_inputs
        outputs = non_ansi_outputs
        inouts = non_ansi_inouts
    else:
        inputs = ansi_inputs
        outputs = ansi_outputs
        inouts = ansi_inouts
    
    # Remove duplicates while preserving order
    inputs = list(dict.fromkeys(inputs))
    outputs = list(dict.fromkeys(outputs))
    inouts = list(dict.fromkeys(inouts))
    
    # Treat inouts as both inputs and outputs for display purposes
    all_inputs = inputs + inouts
    all_outputs = outputs + inouts
    
    return module_name, all_inputs, all_outputs

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

def process_directory(directory_path, output_dir=None, debug=False):
    """Process all Verilog files in a directory."""
    
    dir_path = Path(directory_path)
    
    if not dir_path.exists():
        print(f"Error: Directory '{directory_path}' not found")
        return False
    
    if not dir_path.is_dir():
        print(f"Error: '{directory_path}' is not a directory")
        return False
    
    # Find all Verilog files (.v and .sv extensions)
    verilog_files = list(dir_path.glob('*.v')) + list(dir_path.glob('*.sv'))
    
    if not verilog_files:
        print(f"No Verilog files (.v or .sv) found in '{directory_path}'")
        return False
    
    print(f"\n{'='*70}")
    print(f"Found {len(verilog_files)} Verilog file(s) in '{directory_path}'")
    print(f"{'='*70}\n")
    
    success_count = 0
    fail_count = 0
    
    for verilog_file in sorted(verilog_files):
        print(f"\n{'─'*70}")
        print(f"Processing: {verilog_file.name}")
        print(f"{'─'*70}")
        
        # Determine output file path
        if output_dir:
            output_path = Path(output_dir)
            output_path.mkdir(parents=True, exist_ok=True)
            output_file = output_path / (verilog_file.stem + '_symbol.svg')
        else:
            output_file = verilog_file.parent / (verilog_file.stem + '_symbol.svg')
        
        if verilog_to_svg(str(verilog_file), str(output_file), debug):
            success_count += 1
        else:
            fail_count += 1
    
    # Summary
    print(f"\n{'='*70}")
    print(f"SUMMARY:")
    print(f"  ✅ Successfully processed: {success_count}")
    print(f"  ❌ Failed: {fail_count}")
    print(f"  📊 Total: {len(verilog_files)}")
    print(f"{'='*70}\n")
    
    return fail_count == 0

def main():
    parser = argparse.ArgumentParser(
        description='Generate SVG block symbol from Verilog module(s)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process a single file
  %(prog)s module.v
  
  # Process a single file with custom output
  %(prog)s module.v -o output.svg
  
  # Process all Verilog files in a directory
  %(prog)s -d ./verilog_files/
  
  # Process directory with custom output location
  %(prog)s -d ./verilog_files/ -o ./svg_output/
  
  # Enable debug mode
  %(prog)s module.v --debug
        """
    )
    
    # Make input optional when using directory mode
    parser.add_argument('input', nargs='?', help='Input Verilog file (not needed if using -d)')
    parser.add_argument('-d', '--directory', help='Process all .v and .sv files in this directory')
    parser.add_argument('-o', '--output', help='Output SVG file or directory (default: same location as input with _symbol.svg suffix)')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    
    args = parser.parse_args()
    
    # Check if we have either input file or directory
    if not args.input and not args.directory:
        parser.error("Either provide an input file or use -d/--directory option")
    
    # Directory mode
    if args.directory:
        if not process_directory(args.directory, args.output, args.debug):
            sys.exit(1)
    # Single file mode
    else:
        if not verilog_to_svg(args.input, args.output, args.debug):
            sys.exit(1)

if __name__ == '__main__':
    main()