# CLAHE FPGA Project Guide

**Current language: English** | [中文说明](README_ZH.md)

This repository ships two reproducible FPGA implementations of Contrast Limited Adaptive Histogram Equalization (CLAHE): an earlier 16-tile pipeline for education and the production-ready 64-tile design. Each variant bundles RTL sources, self-checking testbenches, simulation scripts, debug artefacts, and fully curated documentation.

## Overview

- **Algorithm**: Frame-level ping-pong architecture with histogram statistics and mapping in parallel. The 64-tile branch targets 8×8 tiles at 1280×720 @ 30 fps; the 16-tile branch keeps a smaller footprint for teaching.
- **Status**: RTL + simulation complete. Scripts cover ModelSim/Questa, Synopsys VCS, and Icarus Verilog. Waveforms, logs, and BMP snapshots are included for reproducibility.
- **Documentation**: Each branch exposes a `docs/` tree (Quick Start, Architecture, Optimization, Change Logs) ready for hand-off or onboarding.

## Repository Layout

```
CLAHE/
├── README*.md                     # Language entry points
├── projects/
│   ├── 16tile/                    # Legacy 4×4/16-tile reference
│   │   ├── rtl/, tb/, sim/, scripts/, assets/
│   │   └── docs/ + README.md
│   └── 64tile/                    # Main 8×8/64-tile implementation
│       ├── rtl/, tb/, sim/, scripts/, assets/
│       └── docs/ + README.md
├── flows/
│   └── full_sim/                  # End-to-end BMP simulation flow
└── assets/                        # Shared demo images (top-level when needed)
```

> Tip: Branch-level READMEs remain Chinese-first; see `docs/README.md` and `docs/RTL_OVERVIEW.md` for the freshest architecture notes.

## Getting Started

1. **Install tooling**
   - ModelSim/Questa, Synopsys VCS, or Icarus Verilog (see scripts under `full_sim/`).
   - Python 3 for helper scripts such as `verify_cdf_golden.py`.
2. **Pick a branch**
   - `projects/16tile/` for lightweight study or demos.
   - `projects/64tile/` for the full feature set and latest fixes.
3. **Read the docs**
   - `docs/QUICKSTART.md` for the 5-minute tour.
   - `docs/README.md` for deep dives into architecture and integration.
4. **Run simulations**
   ```bash
   cd projects/64tile/sim
   vsim -do run_all.do
   ```
   Or switch to `full_sim/sim_clahe_bmp.do` for frame-based BMP testing across toolchains.

## Documentation Map

- `docs/README.md`: primary guide, quick start, architecture updates, optimization notes, interpolation integration, etc.
- `docs/RTL_OVERVIEW.md`: RTL module-level explanations.
- Stand-alone reports live under `docs/reports/`, grouped by topic.

## Simulation & Test Assets

- `tb/`: module and top-level testbenches with reference waveforms (`.vcd/.view`) and BMP outputs.
- `sim/`: ModelSim/Questa automation (`.do` / `.tcl`) for batch regressions.
- `full_sim/`: BMP-in/BMP-out validation pipeline shared across simulators, producing `sim_log*.txt` and captured frames.
- `scripts/`: reusable `.do/.tcl/.py/.ps1` utilities (per project).
- `verify_cdf_golden.py`: Python golden-model checker (now in each project's `scripts/` folder).

## Data, Logs, and Generated Files

- `assets/images/` and `bmp_test_results/`: curated image sets for reproducibility (only final inputs/outputs remain under version control).
- Waveforms/logs are generated on demand and should be discarded locally after inspection; the repository intentionally keeps them out of source control.

## Contribution Tips

- Base new development on `projects/64tile/` and update `docs/ARCHITECTURE_UPDATE_NOTES.md` when RTL or flow changes.
- When adding scripts or datasets, drop lightweight notes (`README.md` or `docs/NEW_FEATURE.md`) next to them to keep the tree discoverable.

Happy hacking with CLAHE on FPGA! 🚀


