# GCS Storage Plugin Modifications

## Overview

Direct modifications to the `snakemake-storage-plugin-gcs` package to optimize inventory and existence checking for large Snakemake workflows.

**Performance Impact**: Reduces GCS API calls from 100,000+ to 1, cutting DAG building time from 30-60 minutes to 41 seconds (40-90x speedup).

## Problem

The original plugin performs inventory at the deepest subfolder level for each accessed file, resulting in:

- Thousands of separate `list_blobs()` API calls
- 30-60 minutes of overhead for workflows with 100K+ files
- Repeated API calls for files in the same parent directory

## Solution

Modified `inventory()` to list at the workflow root level instead of per-subfolder:

1. Extract top-level directory from blob path
2. Perform single `list_blobs()` call for entire workflow directory tree
3. Cache all files (inputs, outputs, intermediates) in one operation
4. Mark bucket as inventoried to prevent redundant API calls

## Implementation Details

**Type**: Direct modification to installed package source code

**File**: `snakemake_storage_plugin_gcs/__init__.py` in the `brieflow_qinling` conda environment

**Location**: `/home/matteodibernardo/miniconda3/envs/brieflow_qinling/lib/python3.11/site-packages/snakemake_storage_plugin_gcs/__init__.py`

### Class-Level Cache Variables (Lines 273-275)

```python
_inventory_caches = {}          # {bucket_name: IOCacheStorageInterface}
_inventoried_prefixes = set()   # (bucket_name, prefix) tuples
_negative_cache = set()         # cache_key strings for non-existent files
```

**Purpose**:
- **`_inventory_caches`**: Stores cache references by bucket, allowing all instances to access inventory data
- **`_inventoried_prefixes`**: Tracks inventoried bucket/prefix combinations to prevent redundant API calls
- **`_negative_cache`**: Caches non-existent files to avoid repeated API calls during job selection

### Optimization 1: `StorageObject.inventory()` (Lines 289-380)

**Key modifications**:

1. **Workflow root-level listing**: Changed from deep subfolder to top-level directory
2. **Prevent redundant inventories**: Cache marker + class-level tracking
3. **Store cache reference globally**: Accessible to all instances
4. **Performance logging**: Track blob count and elapsed time
5. **Progress tracking**: Log every 10,000 files

### Optimization 2: `StorageObject.exists()` (Lines 398-462)

**Three-tier caching strategy**:

1. **Negative cache check**: Return False immediately if previously determined non-existent
2. **Inventory cache checking**: Use cached inventory if available
3. **API call fallback**: Only if no cache available

## Performance Results

**Test case**: Workflow with 86,516 files

- **Before**: 30-60 minutes (100K+ individual API calls)
- **After**: 41 seconds (1 bulk list operation)
- **Speedup**: ~40-90x for DAG building phase

## Required Snakemake Configuration

These flags work in conjunction with the plugin optimizations:

```bash
snakemake \
    --max-inventory-time 300 \      # Allow up to 5 minutes for inventory
    --latency-wait 0 \               # No wait for files to appear
    --max-checksum-file-size 0 \     # Skip checksums
    --ignore-incomplete \            # Continue despite incomplete files
    --scheduler greedy \             # Greedy scheduling for large DAGs
    --debug-dag                      # Show DAG evaluation progress
```

**Critical flags**:
- **`--max-inventory-time 300`**: Allows bulk inventory to complete for large workflows
- **`--latency-wait 0`**: Avoids unnecessary wait times (GCS is immediately consistent)
- **`--max-checksum-file-size 0`**: Disables checksum computation

## Compatibility

- Backward compatible with existing code
- No API changes required
- Works with existing Snakemake configurations
- Environment-specific (modifications persist in conda environment)

## Trade-offs

**Pros**:
- Dramatically reduces API calls and inventory time
- Optimal for Snakemake workflows with hierarchical file organization
- Maintains all existing functionality

**Cons**:
- May list more files than strictly necessary for deep directory hierarchies
- First inventory call takes longer (but only happens once)
- Changes are lost if conda environment is recreated or package is updated

## Maintenance Notes

**Important**: These modifications are environment-specific and will be lost if:
1. The conda environment is recreated
2. The `snakemake-storage-plugin-gcs` package is updated

**Recommendation**: Maintain a backup of the modified `__init__.py` file for future environments.

**Modified Lines Summary**:
- 273-275: Class-level cache variables
- 289-380: `inventory()` method - workflow root-level listing
- 398-462: `exists()` method - three-tier caching strategy

---

**Last Updated**: 2025-10-22
