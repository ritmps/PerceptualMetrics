# PerceptualMetrics

Perceptual metrics experiments with PyTorch and Wolfram Language integration.

---

## 1. Virtual Environment & Wolfram Language Support

This project is managed with [`uv`](https://github.com/astral-sh/uv).

### Required Packages for Wolfram Language

- **`wolframclient`**: The official Wolfram Client Library for Python. Enables evaluation of Wolfram Language expressions via local kernels (Mathematica / Wolfram Engine) or the Wolfram Cloud.
- **`pyzmq`**: ZeroMQ library used under the hood for binary socket communication with the local Wolfram Kernel.
- **`aiohttp` & `requests`**: Async and sync HTTP clients used for Wolfram Cloud interactions.
- **`pillow` & `numpy`**: Serializes Wolfram `Image` and numeric arrays (`NumericArray`, `PackedArray`) to/from PIL and NumPy formats.
- **`wolframalpha`** *(optional)*: Wrapper for the Wolfram|Alpha API.

### Environment Setup

```bash
# Create venv and install all dependencies using uv
uv sync
```

### Wolfram Language Quickstart in Python

```python
from wolframclient.evaluation import WolframLanguageSession
from wolframclient.language import wl, wlexpr

# 1. Connect to local Mathematica / Wolfram Engine kernel
session = WolframLanguageSession('/Applications/Wolfram.app/Contents/MacOS/WolframKernel')

# 2. Evaluate Wolfram Language expressions
result = session.evaluate(wl.Plus(1, 2))
print("1 + 2 =", result)  # 3

# 3. Evaluate raw WL string expressions
norm_val = session.evaluate(wlexpr("EuclideanDistance[{1, 2}, {4, 6}]"))
print("Distance:", norm_val)  # 5

session.terminate()
```

---

## 2. Note: Mac-Accelerated PyTorch (Apple Silicon / MPS)

On Apple Silicon (M1/M2/M3/M4) macOS systems, hardware acceleration uses Apple's **Metal Performance Shaders (MPS)** backend.

### Installation

Standard PyPI wheels for macOS ARM64 include MPS support natively out of the box:

```bash
uv add torch torchvision torchaudio
# Or in an active venv:
uv pip install torch torchvision torchaudio
```

### Verification & Usage in Python

```python
import torch

print("PyTorch version:", torch.__version__)
print("MPS built:", torch.backends.mps.is_built())
print("MPS available:", torch.backends.mps.is_available())

# Automatically select MPS if available
device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
print("Using device:", device)

x = torch.randn(1000, 1000, device=device)
y = torch.matmul(x, x)
```

### Useful Environment Variables for MPS
- **`PYTORCH_ENABLE_MPS_FALLBACK=1`**: Falls back to CPU if an unsupported PyTorch operation is encountered instead of crashing.
- **`PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0`**: Adjusts unified memory upper bound (default is 1.4x recommended RAM limit).

---

## 3. Note: CUDA-Accelerated PyTorch (NVIDIA / Linux & Windows)

For systems with NVIDIA GPUs, PyTorch distributes dedicated CUDA wheels through official PyTorch wheel indexes.

### Installation via `uv`

#### Ad-hoc / Command Line
Specify the PyTorch wheel index for your installed CUDA driver version (e.g., CUDA 12.6 or 12.8):

```bash
# For CUDA 12.6 (recommended default):
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# For CUDA 12.8 (latest architectures):
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# For CUDA 12.4:
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
```

#### Declarative via `pyproject.toml` (Multi-Platform)
In `pyproject.toml`, configure `tool.uv.sources` so that CUDA wheels are resolved on Linux/Windows, while standard MPS wheels are used on macOS:

```toml
[tool.uv.sources]
torch = [
    { index = "pytorch-cu126", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]
torchvision = [
    { index = "pytorch-cu126", marker = "sys_platform == 'linux' or sys_platform == 'win32'" },
]

[[tool.uv.index]]
name = "pytorch-cu126"
url = "https://download.pytorch.org/whl/cu126"
explicit = true
```

### Verification & Usage in Python

```python
import torch

print("PyTorch version:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("Device name:", torch.cuda.get_device_name(0))
    print("CUDA version:", torch.version.cuda)

# Device selection
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Using device:", device)

x = torch.randn(1000, 1000, device=device)
y = torch.matmul(x, x)
```
