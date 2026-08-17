#!/usr/bin/env bash
# ==============================================================================
# PerceptualMetrics Setup & Installation Script
# Supports Linux and macOS
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for terminal output
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

info() {
    echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $1"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${RESET} $1"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET} $1"
}

show_help() {
    cat << EOF
PerceptualMetrics Installer

Usage:
    ./install.sh [OPTIONS]

Options:
    -h, --help              Show this help message
    --check                 Run diagnostic check on existing environment without reinstalling
    --no-cuda               Force CPU-only PyTorch install on Linux
    --paclet                Register or build the Wolfram Paclet
    --clean                 Remove existing .venv before installing

Examples:
    ./install.sh            # Standard installation (auto-detects uv / python / CUDA / MPS)
    ./install.sh --check    # Check existing installation
EOF
}

CHECK_ONLY=false
FORCE_CPU=false
CLEAN_INSTALL=false
REGISTER_PACLET=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --no-cuda)
            FORCE_CPU=true
            shift
            ;;
        --clean)
            CLEAN_INSTALL=true
            shift
            ;;
        --paclet)
            REGISTER_PACLET=true
            shift
            ;;
        *)
            warn "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BOLD}======================================================${RESET}"
echo -e "${BOLD}         PerceptualMetrics Package Installer         ${RESET}"
echo -e "${BOLD}======================================================${RESET}"

# 1. Check / Initialize Git Submodule
info "Checking git submodules..."
if [ -d ".git" ]; then
    if [ ! -f "PerceptualSimilarity/setup.py" ] && [ ! -f "PerceptualSimilarity/lpips/__init__.py" ]; then
        info "Initializing PerceptualSimilarity submodule..."
        git submodule update --init --recursive
        success "Submodule initialized."
    else
        success "Submodule PerceptualSimilarity is present."
    fi
else
    if [ -d "PerceptualSimilarity" ]; then
        success "PerceptualSimilarity directory is present."
    else
        warn "Not a git repo and PerceptualSimilarity folder is missing."
    fi
fi

# Clean install if requested
if [ "$CLEAN_INSTALL" = true ] && [ -d ".venv" ]; then
    info "Removing existing .venv as requested by --clean..."
    rm -rf .venv
fi

# 2. Check Only Mode
if [ "$CHECK_ONLY" = true ]; then
    info "Running diagnostic check..."
    PYTHON_EXEC=""
    if [ -f ".venv/bin/python" ]; then
        PYTHON_EXEC=".venv/bin/python"
    elif [ -f ".venv/Scripts/python.exe" ]; then
        PYTHON_EXEC=".venv/Scripts/python.exe"
    elif command -v python3 &>/dev/null; then
        PYTHON_EXEC="$(command -v python3)"
    fi

    if [ -n "$PYTHON_EXEC" ]; then
        info "Using Python: $PYTHON_EXEC"
        "$PYTHON_EXEC" -c "
import sys
print(f'Python Version: {sys.version}')
try:
    import torch
    print(f'PyTorch Version: {torch.__version__}')
    print(f'CUDA Available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'CUDA Device: {torch.cuda.get_device_name(0)}')
    if hasattr(torch.backends, 'mps'):
        print(f'MPS Available: {torch.backends.mps.is_available()}')
except ImportError:
    print('PyTorch: NOT INSTALLED')

try:
    import lpips
    print('LPIPS: INSTALLED')
except ImportError:
    print('LPIPS: NOT INSTALLED')

try:
    import wolframclient
    print('WolframClient: INSTALLED')
except ImportError:
    print('WolframClient: NOT INSTALLED')
"
        success "Diagnostic check complete."
        exit 0
    else
        error "No Python executable found to check."
        exit 1
    fi
fi

# 3. Environment Setup (uv or standard python3 venv)
OS_TYPE="$(uname -s)"
info "Detected OS: $OS_TYPE"

HAS_NVIDIA=false
if [ "$OS_TYPE" = "Linux" ] && [ "$FORCE_CPU" = false ]; then
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            HAS_NVIDIA=true
            info "NVIDIA GPU detected via nvidia-smi."
        fi
    fi
fi

if command -v uv &>/dev/null; then
    info "Found 'uv' package manager. Using uv for fast installation..."
    if [ "$HAS_NVIDIA" = true ]; then
        info "Syncing dependencies with CUDA support..."
    fi
    uv sync
    success "Virtual environment (.venv) successfully created/synced with uv."
else
    info "'uv' not found. Falling back to standard python3 venv..."
    if ! command -v python3 &>/dev/null; then
        error "python3 is not installed or not in PATH. Please install Python 3.10+."
        exit 1
    fi

    PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    info "Detected Python version: $PY_VER"

    if [ ! -d ".venv" ]; then
        info "Creating virtual environment in .venv..."
        python3 -m venv .venv
    fi

    VENV_PIP=".venv/bin/pip"
    VENV_PY=".venv/bin/python"

    info "Upgrading pip, setuptools, wheel..."
    "$VENV_PIP" install --upgrade pip setuptools wheel

    if [ "$HAS_NVIDIA" = true ]; then
        info "Installing PyTorch with CUDA 12.6 support..."
        "$VENV_PIP" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
    else
        info "Installing standard PyTorch..."
        "$VENV_PIP" install torch torchvision torchaudio
    fi

    info "Installing project dependencies..."
    "$VENV_PIP" install -e PerceptualSimilarity
    "$VENV_PIP" install numpy pillow scipy scikit-image tqdm requests pyzmq aiohttp statsmodels wolframclient wolframalpha
    success "Virtual environment (.venv) successfully configured."
fi

# 4. Verify Installation
info "Verifying PyTorch and bridge setup..."
VENV_PY=".venv/bin/python"
if [ ! -f "$VENV_PY" ] && [ -f ".venv/Scripts/python.exe" ]; then
    VENV_PY=".venv/Scripts/python.exe"
fi

if [ -f "$VENV_PY" ]; then
    "$VENV_PY" -c "
import torch, torchvision, numpy, PIL, lpips
print(' PyTorch:', torch.__version__)
if torch.cuda.is_available():
    print(' Hardware Acceleration: CUDA (', torch.cuda.get_device_name(0), ')')
elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
    print(' Hardware Acceleration: Apple Silicon MPS')
else:
    print(' Hardware Acceleration: CPU')
"
fi

# 5. Paclet Handling / Optional Registration
if command -v wolframscript &>/dev/null; then
    info "Found wolframscript."
    if [ "$REGISTER_PACLET" = true ]; then
        info "Registering Paclet directory with Wolfram Language..."
        wolframscript -code 'PacletDirectoryLoad["'$SCRIPT_DIR'"]; Print["Paclet loaded: ", PacletObject["PerceptualMetrics"]];'
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo -e "${GREEN}${BOLD}       PerceptualMetrics is Ready to Use!            ${RESET}"
echo -e "${GREEN}${BOLD}======================================================${RESET}"
echo ""
echo -e "To use in ${BOLD}Wolfram Language / Mathematica${RESET}:"
echo ""
echo -e "  ${BOLD}Method 1 (Paclet Directory Load - Recommended):${RESET}"
echo -e "    PacletDirectoryLoad[\"$SCRIPT_DIR\"];"
echo -e "    Needs[\"PerceptualMetrics\`\"];"
echo -e "    PerceptualDoctor[] (* Verify environment *)"
echo ""
echo -e "  ${BOLD}Method 2 (Direct File Get):${RESET}"
echo -e "    Get[\"$SCRIPT_DIR/PerceptualMetrics.wl\"];"
echo -e "    d = PerceptualDistance[img1, img2];"
echo ""
echo -e "  ${BOLD}Method 3 (Permanent Paclet Install):${RESET}"
echo -e "    PacletInstall[\"$SCRIPT_DIR\"];"
echo -e "    Needs[\"PerceptualMetrics\`\"];"
echo ""
