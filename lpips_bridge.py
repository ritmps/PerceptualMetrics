from pathlib import Path
import numpy as np
import torch
from PIL import Image
import lpips as lpips_lib

_loss_fn_cache = {}

def get_device(device=None):
    """Resolve the torch execution device (cuda, mps, cpu)."""
    if device is not None:
        if isinstance(device, str) and device.lower() in ("auto", "automatic"):
            device = None
        else:
            return torch.device(device)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")

def get_loss_fn(metric="lpips", net="alex", version="0.1", lpips=True, colorspace="Lab", spatial=False, device=None):
    """Retrieve or create cached loss model instance."""
    dev = str(get_device(device))
    metric = metric.lower()
    net = net.lower()
    colorspace = colorspace.upper() if isinstance(colorspace, str) else "LAB"
    lpips_flag = bool(lpips)
    spatial_flag = bool(spatial)
    key = (metric, net, version, lpips_flag, colorspace, spatial_flag, dev)

    if key not in _loss_fn_cache:
        if metric == "lpips":
            model = lpips_lib.LPIPS(net=net, version=version, lpips=lpips_flag, spatial=spatial_flag, verbose=False)
            model = model.to(dev)
            model.eval()
        elif metric == "l2":
            model = lpips_lib.L2(colorspace=colorspace)
            model = model.to(dev)
            model.eval()
        elif metric == "dssim":
            model = lpips_lib.DSSIM(colorspace=colorspace)
            model = model.to(dev)
            model.eval()
        elif metric == "psnr":
            model = None
        else:
            raise ValueError(f"Unknown metric '{metric}'. Expected one of ['lpips', 'l2', 'dssim', 'psnr'].")
        _loss_fn_cache[key] = model

    return _loss_fn_cache[key]

def lpips_info():
    """Return status and capability metadata for the bridge session."""
    dev = get_device()
    return {
        "status": "ok",
        "pytorch_version": torch.__version__,
        "device": str(dev),
        "mps_available": hasattr(torch.backends, "mps") and torch.backends.mps.is_available(),
        "cuda_available": torch.cuda.is_available(),
        "metrics": ["lpips", "l2", "dssim", "psnr"],
        "nets": ["alex", "vgg", "squeeze"],
        "versions": ["0.1", "0.0"],
        "colorspaces": ["Lab", "RGB"],
    }

def load_image_tensor(path, device=None):
    """Load image from filepath to 1x3xHxW PyTorch tensor in [-1, +1]."""
    img = Image.open(path).convert("RGB")
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = arr * 2.0 - 1.0
    arr = np.transpose(arr, (2, 0, 1))
    return torch.tensor(arr, dtype=torch.float32).unsqueeze(0).to(get_device(device))

def tensor_from_hwc_rgb01(array, device=None):
    """Convert HWC RGB array in [0, 1] to 1x3xHxW PyTorch tensor in [-1, +1]."""
    arr = np.asarray(array, dtype=np.float32)
    if arr.ndim == 2:  # Grayscale image (H, W) -> RGB (H, W, 3)
        arr = np.stack([arr] * 3, axis=-1)
    elif arr.shape[-1] == 4:  # RGBA -> RGB
        arr = arr[..., :3]
    arr = arr * 2.0 - 1.0
    arr = np.transpose(arr, (2, 0, 1))
    return torch.tensor(arr, dtype=torch.float32).unsqueeze(0).to(get_device(device))

def _to_tensor(item, device=None):
    """Helper to convert filepath string or NumPy array to PyTorch tensor."""
    if isinstance(item, (str, Path)):
        return load_image_tensor(item, device=device)
    else:
        return tensor_from_hwc_rgb01(item, device=device)

def compute_distance(im1, im2, metric="lpips", net="alex", version="0.1", spatial=False, device=None, lpips=True, colorspace="Lab"):
    """Compute perceptual distance (scalar or spatial map) between two images or paths."""
    metric = metric.lower()
    t1 = _to_tensor(im1, device=device)
    t2 = _to_tensor(im2, device=device)

    with torch.no_grad():
        if metric == "psnr":
            arr1 = (t1[0].cpu().numpy().transpose(1, 2, 0) + 1.0) / 2.0
            arr2 = (t2[0].cpu().numpy().transpose(1, 2, 0) + 1.0) / 2.0
            mse = np.mean((arr1 - arr2) ** 2)
            if spatial:
                return np.mean((arr1 - arr2) ** 2, axis=-1)
            if mse == 0:
                return float("inf")
            val = 10.0 * np.log10(1.0 / mse)
            return float(val)

        loss_fn = get_loss_fn(metric=metric, net=net, version=version, lpips=lpips, colorspace=colorspace, spatial=spatial, device=device)
        res = loss_fn(t1, t2)

        if spatial:
            if metric == "lpips":
                return res[0, 0].cpu().numpy()
            elif metric == "l2":
                if colorspace.upper() == "RGB":
                    diff_map = torch.mean((t1 - t2) ** 2, dim=1)[0].cpu().numpy()
                    return diff_map
                else:  # Lab space
                    im1_lab = lpips_lib.tensor2np(lpips_lib.tensor2tensorlab(t1.data, to_norm=False))
                    im2_lab = lpips_lib.tensor2np(lpips_lib.tensor2tensorlab(t2.data, to_norm=False))
                    return np.mean((im1_lab - im2_lab) ** 2, axis=-1) / (100.0 ** 2)
            elif metric == "dssim":
                im1_np = lpips_lib.tensor2im(t1.data)
                im2_np = lpips_lib.tensor2im(t2.data)
                try:
                    from skimage.metrics import structural_similarity as compare_ssim
                    _, ssim_map = compare_ssim(im1_np, im2_np, data_range=255.0, channel_axis=-1, full=True)
                except (ImportError, TypeError):
                    from skimage.measure import compare_ssim
                    _, ssim_map = compare_ssim(im1_np, im2_np, data_range=255.0, multichannel=True, full=True)
                res_map = (1.0 - ssim_map) / 2.0
                if res_map.ndim == 3:
                    res_map = np.mean(res_map, axis=-1)
                return res_map
        else:
            return float(res.item() if isinstance(res, torch.Tensor) else res)

def lpips_distance(path1, path2, net="alex", version="0.1", spatial=False, device=None, lpips=True, metric="lpips", colorspace="Lab"):
    """Compute distance between two image files."""
    return compute_distance(path1, path2, metric=metric, net=net, version=version, spatial=spatial, device=device, lpips=lpips, colorspace=colorspace)

def lpips_distance_batch(pairs, net="alex", version="0.1", spatial=False, device=None, lpips=True, metric="lpips", colorspace="Lab"):
    """Compute distances for a batch of image file pairs."""
    results = []
    for path1, path2 in pairs:
        res = compute_distance(path1, path2, metric=metric, net=net, version=version, spatial=spatial, device=device, lpips=lpips, colorspace=colorspace)
        results.append(res)
    return results

def lpips_distance_array(arr1, arr2, net="alex", version="0.1", spatial=False, device=None, lpips=True, metric="lpips", colorspace="Lab"):
    """Compute distance between two HWC RGB numpy arrays."""
    return compute_distance(arr1, arr2, metric=metric, net=net, version=version, spatial=spatial, device=device, lpips=lpips, colorspace=colorspace)

def lpips_distance_spatial(path1, path2, net="alex", version="0.1", device=None, lpips=True, metric="lpips", colorspace="Lab"):
    """Compute spatial distance map for two image files. Returns 2D float NumPy array (H x W)."""
    return compute_distance(path1, path2, metric=metric, net=net, version=version, spatial=True, device=device, lpips=lpips, colorspace=colorspace)

def lpips_distance_spatial_array(arr1, arr2, net="alex", version="0.1", device=None, lpips=True, metric="lpips", colorspace="Lab"):
    """Compute spatial distance map for two HWC RGB numpy arrays. Returns 2D float NumPy array (H x W)."""
    return compute_distance(arr1, arr2, metric=metric, net=net, version=version, spatial=True, device=device, lpips=lpips, colorspace=colorspace)

def l2_distance(im1, im2, colorspace="Lab", spatial=False, device=None):
    """Shortcut function for L2 distance."""
    return compute_distance(im1, im2, metric="l2", colorspace=colorspace, spatial=spatial, device=device)

def dssim_distance(im1, im2, colorspace="Lab", spatial=False, device=None):
    """Shortcut function for DSSIM distance."""
    return compute_distance(im1, im2, metric="dssim", colorspace=colorspace, spatial=spatial, device=device)

def psnr_distance(im1, im2, spatial=False, device=None):
    """Shortcut function for PSNR distance in dB."""
    return compute_distance(im1, im2, metric="psnr", spatial=spatial, device=device)