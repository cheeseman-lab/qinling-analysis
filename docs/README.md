# Brieflow Google Batch Documentation

This directory contains comprehensive documentation for running Brieflow workflows on Google Cloud Batch with performance optimizations.

## Quick Start

1. **Setup**: Follow `GOOGLE_BATCH_SETUP.md` for initial configuration
2. **Run workflows**: Use batch scripts in `analysis/` directory
3. **Monitor performance**: Check `OPTIMIZATION_SUMMARY.md` for expected timings

## Documentation Files

### 📘 GOOGLE_BATCH_SETUP.md
**Complete setup guide for Google Batch**

Topics covered:
- Prerequisites and infrastructure setup
- Docker image configuration
- Workflow profile configuration
- Data management and GCS utilities
- Running workflows
- Monitoring and debugging
- Cost optimization

**Start here if**: You're setting up Google Batch for the first time.

### 📊 OPTIMIZATION_SUMMARY.md
**Overview of all performance optimizations**

Topics covered:
- Problem identification and root causes
- All four optimization strategies
- Performance metrics (13+ hours → ~30 minutes)
- Files modified and configuration changes
- Troubleshooting guide

**Start here if**: You want to understand how we achieved 50x speedup.

### 🔧 PLUGIN_CHANGES.md
**GCS storage plugin source code modifications**

Topics covered:
- Plugin inventory optimization details
- Three-tier caching strategy
- Implementation details (lines modified)
- Required Snakemake configuration
- Maintenance notes

**Start here if**: You need to recreate the plugin modifications in a new environment.

### 🩹 GCS_PATCH.md
**Job scheduler runtime patch documentation**

Topics covered:
- Patch architecture and how it works
- Configuration via environment variables
- Expected output and performance metrics
- Integration with plugin optimization
- Troubleshooting

**Start here if**: You need to debug or modify the job scheduler patch.

## Performance Summary

With all optimizations applied:

| Phase | Time | Description |
|-------|------|-------------|
| DAG Building | ~10 min | GCS plugin bulk inventory (86K files) |
| Job Selection | ~5 sec | Job scheduler patch bulk inventory |
| Job Submission | Instant | All jobs submitted at once |
| Execution | ~12-20 min | 2,500 concurrent spot VMs |
| **Total** | **~30 min** | **For 10,000-job workflows** |

**Before optimizations**: 13+ hours

## File Organization

```
docs/
├── README.md                    # This file
├── GOOGLE_BATCH_SETUP.md       # Complete setup guide
├── OPTIMIZATION_SUMMARY.md     # All optimizations overview
├── PLUGIN_CHANGES.md           # GCS plugin modifications
└── GCS_PATCH.md                # Job scheduler patch

analysis/
├── google_batch/
│   ├── config.yaml                     # Google Batch configuration
│   └── gcs_job_scheduler_patch.py      # Patch source (copied to workflow/)
└── *_batch.sh                   # Batch run scripts

brieflow/
└── workflow/
    ├── Snakefile                       # Auto-loads patch
    └── gcs_job_scheduler_patch.py      # Patch (gets packaged for deployment)
```

## Optimizations Applied

1. **GCS Storage Plugin** (conda package modification)
   - Bulk inventory at workflow root level
   - Class-level caching to prevent redundant API calls
   - Three-tier existence checking

2. **Job Scheduler Patch** (runtime patch)
   - Intercepts job selection
   - Bulk GCS inventory before file checks
   - Auto-loaded by Snakefile

3. **Submission Rate** (configuration)
   - `--max-jobs-per-timespan "10000/1s"`
   - Submits all jobs immediately

4. **VM Type & Spot Instances** (configuration)
   - n2-standard-4 VMs (faster provisioning)
   - Spot instances (2,500 concurrent VMs)
   - 60-90% cost savings

## Quick Reference

### Running Workflows

```bash
cd analysis
./1.run_preprocessing_batch.sh  # All optimizations auto-applied
```

### Checking Performance

Look for these indicators:

**DAG Building** (fast):
```
Building DAG of jobs...
[... completes in <15 minutes ...]
```

**Job Selection** (instant):
```
[job_selector] 📦 Doing bulk inventory FIRST...
[GCS Bulk Inventory] ✅ Cached 86,234 files in 4.82s
```

**Job Submission** (all at once):
```
Execute 1754 jobs...  ← All jobs, not batches of 100
```

### Disabling Optimizations

**Disable job scheduler patch**:
```bash
export GCS_JOB_SCHEDULER_PATCH_DISABLE=1
```

**Note**: Plugin modifications are permanent (until package is updated/reinstalled).

## Support

- See individual documentation files for detailed information
- Check troubleshooting sections in each document
- Refer to `OPTIMIZATION_SUMMARY.md` for performance verification

---

**Last Updated**: 2025-10-22
