# Documentation Plan for Pepper_T4 Digital

This document outlines the plan for creating comprehensive documentation for the Pepper_T4 digital Verilog codebase.

## Recommended Tools & Workflow

### 1. Documentation Engine: **MkDocs + Material Theme**
*   **Why**:
    *   **Markdown-based**: Easy to write and version control alongside code.
    *   **Modern UI**: The Material theme is responsive, searchable, and professional.
    *   **Plugin Ecosystem**: Excellent support for **Mermaid** (diagrams) and **MathJax** (formulas).
    *   **Simplicity**: Faster to set up than Sphinx, essentially 1 conceptual step (write `.md` files).
*   **Alternative**: **Sphinx** (if you need heavy cross-referencing or Python auto-docs). MkDocs is generally preferred for pure hardware description/guide documentation.

### 2. Diagramming Tools
*   **Block Diagrams**: **Draw.io** (Desktop or Web).
    *   **Why**: Fully editable, saves as XML (can be checked into git), exports high-res PNG/SVG. Easier to manage sophisticated layout than text-based tools like Graphviz/Mermaid for the top-level.
    *   **Files**: Save `.drawio` files in `docs/diagrams/source` and export images to `docs/diagrams/images`.
*   **State & Logic Diagrams**: **Mermaid.js**.
    *   **Why**: Text-based, renders directly in MkDocs. Easy to edit FSM transitions without redrawing lines.
*   **Timing Diagrams**: **WaveDrom**.
    *   **Why**: Industry standard for digital timing. JSON-based, renders precise clock-cycle diagrams. Can be embedded in MkDocs.

---

## Task Breakdown

### Phase 1: Infrastructure & High-Level (Setup)

| ID | Task Description | Dependencies | AI Complexity | Assigned Model |
| :--- | :--- | :--- | :--- | :--- |
| **1.1** | **Setup Documentation Project**<br>- Initialize MkDocs project.<br>- Configure `mkdocs.yml` with Material theme and plugins (maid, search).<br>- Create folder structure (`docs/`, `docs/images`). | None | **Basic** | **Gemini 3 Flash** |
| **1.2** | **System Overview & Theory of Operation**<br>- Write high-level summary of Pepper_T4.<br>- Describe data flow: SPI -> Command Interpreter -> Registers/Blocks -> Status.<br>- **Important Note**: Document high-level limitations (e.g., sample enabling/disabling). | None | **Middle** | **Gemini 3 Pro** |
| **1.3** | **Top-Level Block Diagram**<br>- Create editable Block Diagram (Draw.io) showing all modules and main interfaces.<br>- Export to PNG for inclusion. | None | **Middle** | **Gemini 3 Pro** |

### Phase 2: Critical Complex Blocks (Core Logic)

| ID | Task Description | Dependencies | AI Complexity | Assigned Model |
| :--- | :--- | :--- | :--- | :--- |
| **2.1** | **Command_Interpreter Documentation**<br>- Explain SPI protocol (Mode 0/3?), command structure (R/W).<br>- **State Diagram** (Mermaid): Visualizing the main FSM (Idle -> Parse -> Read/Write).<br>- **Timing Diagram** (WaveDrom): Show valid transaction sequences.<br>- Document access permissions (sampling vs configuration). | Phase 1 | **Advanced** | **Claude Sonnet 4.5** |
| **2.2** | **FIFO Documentation**<br>- Explain the cross-clock domain architecture (Write clock vs Read clock).<br>- **Diagram**: Pointer arithmetic and gray coding visualization.<br>- Explain "Look-ahead" read behavior.<br>- Document full/empty/overflow/underflow flag logic. | Phase 1 | **Advanced** | **Claude Sonnet 4.5** |
| **2.3** | **CDC_sync & Synchronization**<br>- Explain the 2-stage synchronizer and `toggle` synchronizer for pulses.<br>- **Warning**: Document constraints (source pulse width vs dest clock period). | Phase 1 | **Advanced** | **Claude Sonnet 4.5** |

### Phase 3: Status & Functional Logic

| ID | Task Description | Dependencies | AI Complexity | Assigned Model |
| :--- | :--- | :--- | :--- | :--- |
| **3.1** | **Status Logic & Reset Architecture**<br>- **Diagram** (Mermaid Flowchart): Trace a status event from Source -> Latch -> Sync -> Register -> Host Read -> Clear.<br>- Explain "Write-1-to-Clear" (W1C) mechanism.<br>- Explain how `ensamp` gates status generation. | Phase 1 | **Advanced** | **Claude Sonnet 4.5** |
| **3.2** | **Status_Monitor Documentation**<br>- List all status inputs.<br>- Describe aggregation logic. | Phase 1 | **Basic** | **Gemini 3 Flash** |

### Phase 4: Peripheral Control Blocks

| ID | Task Description | Dependencies | AI Complexity | Assigned Model |
| :--- | :--- | :--- | :--- | :--- |
| **4.1** | **ATM_Control Documentation**<br>- Explain the control sequence for ATM.<br>- **Timing Diagram** (WaveDrom): Show the control signals over time.<br>- **State Diagram**: If implemented as FSM. | Phase 1 | **Middle** | **Gemini 3 Pro** |
| **4.2** | **Configuration_Registers Documentation**<br>- Register Map Table (Address, Name, Description, Defaults).<br>- Explain effect of specific bits (e.g., `GLOBAL_ENABLE`). | Phase 1 | **Basic** | **Gemini 3 Flash** |
| **4.3** | **TempSense / Other Peripherals**<br>- Brief functional description and IO listing. | Phase 1 | **Basic** | **Gemini 3 Flash** |

### Phase 5: Final Review & Integration

| ID | Task Description | Dependencies | AI Complexity | Assigned Model |
| :--- | :--- | :--- | :--- | :--- |
| **5.1** | **Compile & Review**<br>- Build static site (or PDF via plugin).<br>- Review for clarity, consistency, and completeness.<br>- Verify all diagrams render correctly. | All Phases | **Middle** | **Gemini 3 Pro** |

## Diagramming Strategy Summary

1.  **Top Level Interconnect**: **Draw.io** (or format importable into an Altium Schematic).
2.  **State Machines**: **Mermaid** `stateDiagram-v2`.
3.  **Timing**: **WaveDrom** JSON.
4.  **Status Propagation Flow**: **Mermaid** `flowchart LR`.
