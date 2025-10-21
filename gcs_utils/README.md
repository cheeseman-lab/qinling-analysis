# GCS Utilities

Simple scripts for managing Google Cloud Storage data and Google Batch jobs.

## Scripts

| Script | Description | Example |
|--------|-------------|---------|
| `upload_config.sh` | Upload `analysis/config/` to GCS | `./upload_config.sh my_screen` |
| `upload_data.sh` | Upload files/directories to GCS | `./upload_data.sh data/ gs://bucket/path/` |
| `list_data.sh` | List GCS bucket contents | `./list_data.sh gs://bucket/path/` |
| `get_batch_logs.sh` | Get Google Batch job logs | `./get_batch_logs.sh --state FAILED` |
| `delete_output.sh` | Delete GCS outputs ± batch jobs | `./delete_output.sh gs://bucket/output/` |
| `delete_batch_jobs.sh` | Delete batch jobs by state/age | `./delete_batch_jobs.sh --state FAILED` |

## Quick Start

**After running a configuration notebook:**
```bash
gcs_utils/upload_config.sh my_screen
```

**Upload raw imaging data (one-time):**
```bash
gcs_utils/upload_data.sh /path/to/images gs://scale1/input_data/
```

**Check outputs:**
```bash
gcs_utils/list_data.sh gs://scale1/brieflow_output/
```

**Debug failed jobs:**
```bash
gcs_utils/get_batch_logs.sh --state FAILED
```

**Clean up:**
```bash
gcs_utils/delete_batch_jobs.sh --state FAILED
gcs_utils/delete_output.sh gs://scale1/brieflow_output/
```

## Usage Tips

- All scripts show what they'll do and prompt for confirmation
- Use `--help` or `-h` on any script for detailed options
- Scripts use color output to highlight important info
- Upload/delete scripts support dry-run mode (`-n`)

## Common Workflows

**Standard analysis workflow:**
1. Run configuration notebook in `analysis/`
2. `gcs_utils/upload_config.sh my_screen`
3. Run batch script from `analysis/`
4. Repeat for each step

**Debugging workflow failures:**
1. `gcs_utils/get_batch_logs.sh --state FAILED`
2. Check logs in `batch_logs/` directory
3. Fix issues and re-run
4. `gcs_utils/delete_batch_jobs.sh --state FAILED` (cleanup)

**Checking workflow progress:**
```bash
# List running jobs
gcloud batch jobs list --location=us-west1 --filter="state=RUNNING"

# Check output files
gcs_utils/list_data.sh gs://scale1/brieflow_output/ -r
```
