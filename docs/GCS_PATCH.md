# GCS Job Scheduler Patch

## Overview

Runtime patch for Snakemake's job scheduler that intercepts file existence checks and performs bulk GCS inventory before job selection.

**Locations**:
- Source: `analysis/google_batch/gcs_job_scheduler_patch.py`
- Deployed: `brieflow/workflow/gcs_job_scheduler_patch.py` (copied to workflow for packaging)

**Performance Impact**: Reduces job selection time from 40-45 minutes to 5-10 seconds (400x speedup) by replacing 14,000+ individual GCS API calls with a single bulk inventory operation.

## Problem

During job selection, Snakemake checks if each input file exists and gets its size:

- **~14,000 individual file checks** (one per input file)
- **~175ms per check** (even when "trusting inventory")
- **40+ minutes total** for job selection phase

## Solution

The patch intercepts Snakemake's job scheduler to:

1. **Do ONE bulk GCS `list_blobs()` call** at the start (~5 seconds for 86K files)
2. **Cache all file info** (exists, size, mtime) in memory
3. **Use cached data** for all subsequent checks (instant)
4. **Clear cache** after job selection (next round gets fresh data)

## How It Works

### Patching Strategy

The patch modifies three key components:

1. **`JobScheduler.job_selector()`**: Triggers bulk inventory before job selection
2. **`_IOFile.exists()`**: Checks cache first, falls back to original
3. **`_IOFile.size()`**: Returns cached size if available

### Architecture

```
JobScheduler.job_selector() called
  ↓
[PATCH INTERCEPTS]
  ↓
1. Bulk GCS Inventory
   └─ ONE list_blobs() call
   └─ Cache 86,000+ files (~5s)
  ↓
2. Patch _IOFile methods
   └─ Check cache first (instant)
   └─ Fall back to original
  ↓
3. Call original job_selector()
   └─ Uses cached data
   └─ Completes in seconds
```

## Configuration

The patch uses environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GCS_PROJECT` | `lasagna-199723` | GCP project ID |
| `GCS_BUCKET` | `scale1` | GCS bucket name |
| `GCS_PREFIX` | `qinling/` | Prefix to inventory |
| `GCS_JOB_SCHEDULER_PATCH_DISABLE` | `0` | Set to `1` to disable |

**Override defaults**:
```bash
export GCS_PROJECT=my-project
export GCS_BUCKET=my-bucket
export GCS_PREFIX=my-prefix/
```

## Usage

### Automatic Loading

The patch is automatically loaded when the Snakefile imports it (already configured):

```python
# brieflow/workflow/Snakefile (lines 1-19)
# Patch is in the same directory as Snakefile (gets packaged for deployment)
try:
    import gcs_job_scheduler_patch
    print("✓ GCS Job Scheduler Patch loaded successfully", file=sys.stderr)
except ImportError:
    print("⚠ Running without job scheduler optimization", file=sys.stderr)
```

### Disabling the Patch

**Option 1 - Environment variable**:
```bash
export GCS_JOB_SCHEDULER_PATCH_DISABLE=1
./analysis/1.run_preprocessing_batch.sh
```

**Option 2 - Comment out import**:
```python
# import gcs_job_scheduler_patch
```

## Expected Output

```
======================================================================
🔧 Applying GCS Bulk Inventory Patch to Snakemake
======================================================================
✓ Patched _IOFile.exists()
✓ Patched _IOFile.size()
✓ Patched JobScheduler.job_selector to do early inventory

Configuration:
  GCS Project: lasagna-199723
  GCS Bucket:  scale1
  GCS Prefix:  qinling/
======================================================================

Building DAG of jobs...

======================================================================
[job_selector] 🎯 ENTERED
[job_selector] Number of jobs: 1754
[job_selector] 📦 Doing bulk inventory FIRST...
======================================================================
[GCS Bulk Inventory] Starting for gs://scale1/qinling/*
[GCS Bulk Inventory] Processed 10,000 files...
[GCS Bulk Inventory] Processed 20,000 files...
[GCS Bulk Inventory] ✅ Cached 86,234 files in 4.82s
======================================================================
[job_selector] ✅ Inventory complete: 86234 cache entries
[job_selector] Calling original job_selector with cached data...
[job_selector] ✅ Selected 1754 jobs
======================================================================

Execute 1754 jobs...

======================================================================
📊 GCS Job Scheduler Patch Statistics
======================================================================
Inventory operations:  1
Files cached:          86,234
Inventory time:        4.82s
Cache hits:            14,025
Cache misses:          127
Cache hit rate:        99.1%

✅ Excellent cache performance!
   Avoided ~14,025 GCS API calls
======================================================================
```

## Performance Metrics

| Metric | Before Patch | After Patch | Improvement |
|--------|-------------|-------------|-------------|
| Job Selection | 40-45 min | 5-10 sec | **~400x faster** |
| GCS API Calls | 14,000+ | 1 | **99.99% reduction** |
| Total Startup | ~42 min | ~1 min | **40x faster** |

## Multiple Job Selection Rounds

The patch handles multiple rounds correctly:

1. **Round 1**: Bulk inventory → select jobs → clear cache
2. **Round 2**: Bulk inventory → select jobs → clear cache (fresh data)
3. **Round 3**: And so on...

Each round gets fresh data from GCS, ensuring completed job outputs are properly detected.

## Cache Details

### Path Formats Supported

The cache stores each file under three path formats:

1. `gs://scale1/qinling/path/to/file.txt` (GCS URI)
2. `.snakemake/storage/gcs/scale1/qinling/path/to/file.txt` (Snakemake storage)
3. `/mnt/data/blainey/qinling-analysis/gcs/scale1/qinling/path/to/file.txt` (Local mount)

### Memory Usage

With 86,000 files cached:
- ~200 bytes per file entry
- ~17 MB total cache size
- Negligible overhead

### Thread Safety

The patch is safe for concurrent use:
- Cache is populated before any reads
- All reads are from the same dict (no writes during reads)
- Cache is cleared after job selection completes

## Troubleshooting

### "Module not found: gcs_job_scheduler_patch"

**Cause**: Python can't find the patch file.

**Fix**: Verify the file exists:
```bash
ls -l /mnt/data/blainey/qinling-analysis/analysis/google_batch/gcs_job_scheduler_patch.py
```

### "google.cloud not found"

**Cause**: Not in the correct conda environment.

**Fix**:
```bash
conda activate brieflow_qinling
```

### Patch loads but no performance improvement

**Check**:
- Look for "🔧 Applying GCS Bulk Inventory Patch" message (patch loaded)
- Look for "[GCS Bulk Inventory] Starting..." message (inventory running)
- Check statistics at end showing cache hits

### Cache hit rate is low (<50%)

**Cause**: Many files are outside the configured `GCS_PREFIX`.

**Fix**: Set prefix to cover all files:
```bash
export GCS_PREFIX=""  # Empty = entire bucket
```

## Integration

This patch works alongside the GCS plugin inventory optimization:

| Optimization | What It Does | When | Impact |
|-------------|--------------|------|--------|
| **GCS Plugin** | Bulk inventory during DAG building | Once at startup | DAG: 41s |
| **This Patch** | Bulk inventory during job selection | Each job round | Selection: 5s |

Both optimizations are needed for full performance.

---

**Last Updated**: 2025-10-22
