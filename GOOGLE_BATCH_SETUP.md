# Google Batch Setup Guide for Brieflow

This guide provides comprehensive instructions for running Brieflow workflows on Google Cloud Batch, a managed service for running large-scale batch workloads on Google Cloud Platform.

## Table of Contents

1. [Overview](#overview)
2. [Brieflow Analysis Workflow](#brieflow-analysis-workflow)
3. [Prerequisites](#prerequisites)
4. [Infrastructure Setup](#infrastructure-setup)
5. [Docker Image Configuration](#docker-image-configuration)
6. [Workflow Profile Configuration](#workflow-profile-configuration)
7. [Data Management](#data-management)
8. [Running Workflows](#running-workflows)
9. [Performance Optimization](#performance-optimization)
10. [Monitoring and Debugging](#monitoring-and-debugging)
11. [Cost Optimization](#cost-optimization)
12. [Account Permissions Summary](#account-permissions-summary)
13. [Summary Checklist](#summary-checklist)

---

## Overview

Google Batch enables Brieflow to:
- Scale to thousands of parallel jobs automatically
- Use preemptible VMs to reduce costs (up to 80% savings)
- Store data and results in Google Cloud Storage (GCS)
- Avoid managing cluster infrastructure

**Key Architecture:**
- **Controller**: Your VM where you run snakemake (from the `analysis/` directory)
- **Workers**: Google Batch VMs (ephemeral, created per job)
- **Storage**: Google Cloud Storage buckets for data and outputs
- **Container**: Docker image with Brieflow and all dependencies pre-installed

---

## Brieflow Analysis Workflow

This guide is designed for the `analysis/` directory workflow:

**Standard workflow:**
1. **Configure**: Run numbered notebooks (0, 2, 3, 5, 7, 9) to configure each step
2. **Generate configs**: Notebooks update files in `analysis/config/` (config.yml, *.tsv files)
3. **Execute**: Run numbered scripts (1, 4a/4b, 6, 8, 10) to execute each step

**For Google Batch:** Batch-enabled scripts (`*_batch.sh`) have been created that:
- Submit jobs to Google Cloud Batch instead of running locally
- Handle the directory navigation required for proper deployment
- Reference your `analysis/config/` files from GCS

---

## Prerequisites

### Required GCP Services

Enable the following APIs in your GCP project:

```bash
# Set your project ID
PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable batch.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

### Service Account Setup

Create a service account that batch workers will use to access resources:

```bash
# Create service account
SA_NAME="batch-sa"
gcloud iam service-accounts create $SA_NAME \
    --display-name="Batch Service Account for Brieflow" \
    --project=$PROJECT_ID

# Grant project-level roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/batch.agentReporter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/serviceusage.serviceUsageConsumer"
```

**Note:** GCS bucket permissions will be added separately (see Infrastructure Setup section).

### Controller Machine Requirements

The controller machine (where you run `snakemake`) needs:

**1. User Account Permissions:**

Your GCP user account needs the following roles:
- `roles/editor` (or `roles/owner`) - To submit batch jobs and manage resources
- `roles/storage.admin` - To read/write GCS buckets
- `roles/cloudbuild.builds.editor` - To build Docker images
- `roles/batch.jobsEditor` - To create and manage batch jobs

**Verify your permissions:**
```bash
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:YOUR_EMAIL@domain.com"
```

**2. Local Environment Setup:**

```bash
# Create conda environment with snakemake
conda create -n brieflow_SCREEN_NAME python=3.11 -y
conda activate brieflow_SCREEN_NAME

# Install brieflow with Google Batch support
cd brieflow
pip install -e .

# Verify the EXACT executor plugin is installed
pip show snakemake-executor-plugin-googlebatch
```

**CRITICAL:** The `pyproject.toml` file specifies this exact version:
```toml
"snakemake-executor-plugin-googlebatch @ git+https://github.com/mboulton-fathom/snakemake-executor-plugin-googlebatch@feat/allow-custom-containers"
```

This is an **unmerged PR** that adds support for the `googlebatch_container_dependencies_installed` flag. Do NOT use the standard PyPI version - it will not work!

---

## Infrastructure Setup

### 1. Create GCS Bucket

```bash
# Set your bucket configuration
# IMPORTANT: Replace with your own bucket name (must be globally unique)
BUCKET_NAME="your-bucket-name"  # e.g., "scale1", "brieflow-myproject-data"
REGION="us-west1"               # Choose your preferred region
SA_NAME="batch-sa"

# Create bucket
gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME

# Grant service account permissions on bucket
# This allows batch workers to read input data and write outputs
gsutil iam ch \
    serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.admin \
    gs://$BUCKET_NAME

gsutil iam ch \
    serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectAdmin \
    gs://$BUCKET_NAME

# Verify permissions
gsutil iam get gs://$BUCKET_NAME
```

**Important:** Your controller user account should already have bucket access through the `roles/storage.admin` project-level role. The service account needs explicit bucket-level permissions so batch workers can access GCS.

### 2. Create Artifact Registry for Docker Images

```bash
REPO_NAME="brieflow-repo"

# Create Docker repository
gcloud artifacts repositories create $REPO_NAME \
    --repository-format=docker \
    --location=$REGION \
    --project=$PROJECT_ID

# Configure Docker authentication
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 3. Verify Setup

```bash
# List repositories
gcloud artifacts repositories list --location=$REGION

# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

## Docker Image Configuration

### Overview

The Docker image contains Brieflow, all dependencies, and Snakemake with the Google Batch executor plugin pre-installed. Batch workers run this container to execute workflow tasks.

**Key components:**
- Brieflow codebase and Python dependencies
- Snakemake with **unmerged** Google Batch executor plugin (feat/allow-custom-containers branch)
- Conda environment that auto-activates on container start
- Pre-installed dependencies to avoid runtime pip installs

### Key Files (Already Created)

The following files are already set up in the `brieflow/` directory:

**1. `Dockerfile`**
- Based on `continuumio/miniconda3:latest`
- Creates conda environment `brieflow` with Python 3.11
- Installs all dependencies from `pyproject.toml` using `uv` (fast!)
- Copies custom entrypoint script
- Sets working directory to `/workdir`

**2. `docker-entrypoint.sh`**
- Activates the `brieflow` conda environment
- Executes commands passed to the container
- Required because Google Batch doesn't natively support conda

**3. `cloudbuild.yaml`**
- Defines Cloud Build steps (build → push)
- Specifies machine type (E2_HIGHCPU_8) for fast builds
- Sets timeout (3600s = 1 hour)
- Target: `us-west1-docker.pkg.dev/${PROJECT_ID}/brieflow-repo/brieflow:latest`

**4. `build_docker.sh`**
- Wrapper script that runs `gcloud builds submit`
- Update `PROJECT_ID` variable before running
- Submits build to Google Cloud Build (not local docker)

**5. `pyproject.toml`**
- **CRITICAL:** Specifies the exact executor plugin:
  ```toml
  "snakemake-executor-plugin-googlebatch @ git+https://github.com/mboulton-fathom/snakemake-executor-plugin-googlebatch@feat/allow-custom-containers"
  ```
- This is an **unmerged PR branch** - DO NOT use PyPI version!
- Includes all Brieflow dependencies

### Building the Image

```bash
cd brieflow

# Update PROJECT_ID and REGION in build_docker.sh
vim build_docker.sh

# Build and push image using Cloud Build (takes ~10-15 minutes)
bash build_docker.sh

# Verify image was pushed
gcloud artifacts docker images list \
    us-west1-docker.pkg.dev/$PROJECT_ID/brieflow-repo
```

---

## Workflow Profile Configuration

Create a workflow profile directory with a `config.yaml` file that configures Google Batch settings.

**Example:** `google_batch/config.yaml`

```yaml
# Brieflow Google Batch configuration file

# Specify the executor
executor: googlebatch

# Google Batch specific settings
# IMPORTANT: Replace these with your actual values
googlebatch-project: your-project-id           # Your GCP project ID
googlebatch-region: us-west1                   # Your GCP region
googlebatch-service-account: batch-sa@your-project-id.iam.gserviceaccount.com

# Container OS settings - use COS with brieflow container
googlebatch-image-family: "batch-cos-stable-official"
googlebatch-image-project: "batch-custom-image"

# Specify the container image that contains brieflow and all dependencies
# IMPORTANT: Update with your artifact registry path
googlebatch-container: "us-west1-docker.pkg.dev/your-project-id/brieflow-repo/brieflow:latest"

# Use the custom docker-entrypoint.sh to activate conda environment
googlebatch-entrypoint: "/docker-entrypoint.sh"

# CRITICAL: Tell executor dependencies are pre-installed (skips pip install)
googlebatch-container-dependencies-installed: true

# Storage settings - GCS configuration
# IMPORTANT: Replace with your bucket name
default-storage-provider: gcs
storage-gcs-project: your-project-id           # Your GCP project ID
default-storage-prefix: gs://your-bucket-name  # Your GCS bucket (e.g., gs://scale1)

# Keep these on the controller's local filesystem for speed
# IMPORTANT: Including 'sources' packages workflow code with each batch job
# CRITICAL PERFORMANCE OPTIMIZATION:
# Including 'input-output' prevents expensive GCS API calls during DAG building!
# - Without it: 21,552+ API calls for a 10K-job workflow = 5+ hours of DAG building
# - With it: DAG builds in 5-15 minutes
# This is THE MOST IMPORTANT performance optimization for large workflows!
shared-fs-usage:
  - persistence           # Keep metadata/cache local for performance
  - source-cache          # Downloaded packages stay on controller
  - sources               # Package workflow code with each batch job
  - input-output          # ← CRITICAL! Tells Snakemake input/output accessible via GCS (no per-file checks)
  - storage-local-copies  # Helps with caching

# Storage settings for controller VM
local-storage-prefix: /path/to/local/workspace

# Maximum number of concurrent jobs
jobs: unlimited

# Default resources for all rules
# NOTE: n2-standard-4 recommended over c2 (faster provisioning, 20x more quota with spot)
default-resources:
  mem_mb: 5000
  cpus_per_task: 1
  runtime: 400  # in minutes
  googlebatch_machine_type: "n2-standard-4"  # Faster provisioning than c2, better spot quota
  googlebatch_boot_disk_gb: 30
  googlebatch_retry_count: 1
  googlebatch_max_run_duration: "3600s"

# Override resources for specific rules
set-resources:
  # High memory jobs
  combine_reads:
    mem_mb: 20000
  align:
    mem_mb: 980000
    cpus_per_task: 4

  # Multi-CPU jobs
  segment_sbs:
    cpus_per_task: 4
```

### Key Configuration Parameters

| Parameter | Description |
|-----------|-------------|
| `googlebatch-container` | Docker image with pre-installed dependencies |
| `googlebatch-entrypoint` | Custom entrypoint script (activates conda) |
| `googlebatch-container-dependencies-installed` | **CRITICAL**: Set to `true` to skip runtime pip installs |
| `shared-fs-usage: sources` | Packages workflow code with each batch job |
| `default-storage-prefix` | GCS bucket for storing outputs |

### Command-Line Length Considerations

**Issue:** Snakemake encodes each `set-resources` entry as a base64 string and passes them as command-line arguments. Too many entries exceed Linux command-line length limits (~2MB).

**Solution:**
- Keep `set-resources` minimal - only specify values that differ significantly from defaults
- Increase `default-resources.mem_mb` to reduce need for per-rule overrides
- Comment out rules that can use defaults

---

## Data Management

### Prepare Config for Google Batch

**Why this matters:** Batch workers run in isolated VMs and need:
1. Config files (TSV, models) accessible in GCS
2. `config.yml` deployed with the workflow code

After each configuration notebook updates `analysis/config/`, you must run `upload_config.sh` before executing workflows.

**The upload_config.sh script does 3 things:**

```bash
# Replace 'my_screen' with your screen/analysis name
gcs_utils/upload_config.sh my_screen
```

1. **Uploads config files to GCS**: TSV files, models, etc. → `gs://your-bucket/my_screen/config/`
2. **Updates config.yml paths**: Replaces local paths with GCS paths (e.g., `sbs_samples_fp: gs://...`)
3. **Copies config.yml to workflow**: Places the GCS-updated config at `brieflow/workflow/config.yml`

This way:
- Config files are in GCS where batch workers can access them
- config.yml is in the workflow directory where it gets deployed to workers
- All paths in config.yml correctly reference GCS locations

See [`gcs_utils/README.md`](gcs_utils/README.md) for all available utilities.

### Uploading Input Data to GCS

Upload your raw imaging data (one-time setup):

```bash
# IMPORTANT: Replace 'your-bucket' and 'screen-name' with your actual values
# Example: gs://scale1/qinling/input_ph/

# Upload phenotype imaging data to your screen subdirectory
gcs_utils/upload_data.sh /path/to/phenotype/images gs://your-bucket/screen-name/input_ph/

# Verify upload
gcs_utils/list_data.sh gs://your-bucket/screen-name/input_ph/
```

These uploads are typically done once. The `upload_data.sh` script shows file sizes, prompts for confirmation, and verifies successful upload.

See [`gcs_utils/README.md`](gcs_utils/README.md) for more options and utilities.

### Data Organization

The GCS bucket structure is organized by screen name, with the storage prefix pointing to your bucket root.

**How it works:**
- `default-storage-prefix` = bucket root (e.g., `gs://scale1`)
- Screen organization comes from `root_fp` in `config.yml` (e.g., `screen-name/brieflow_output/`)
- Input file paths (from TSV files) are relative to the storage prefix
- Output path = `default-storage-prefix` + `root_fp`

**Example structure** (using `default-storage-prefix: gs://scale1` and screen name `qinling`):

```
gs://scale1/
└── qinling/                     # Your screen subdirectory
    ├── config/                  # Config files (from upload_config.sh qinling)
    │   ├── sbs_samples.tsv
    │   ├── phenotype_samples.tsv
    │   └── ...
    ├── input_ph/                # Input imaging data (uploaded manually)
    │   ├── plate_1/
    │   └── ...
    └── brieflow_output/         # Workflow outputs (from root_fp: qinling/brieflow_output/)
        ├── preprocess/
        ├── sbs/
        ├── phenotype/
        └── ...
```

**Configuration steps:**

1. **Set your storage prefix** (bucket root only):
   - `analysis/google_batch/config.yaml`: `default-storage-prefix: gs://your-bucket`
   - All `analysis/*_batch.sh` scripts: `--default-storage-prefix "gs://your-bucket"`
   - And: `--storage-gcs-project your-project-id`

2. **Set your screen-specific root_fp** in `analysis/config/config.yml`:
   - `root_fp: screen-name/brieflow_output/` (e.g., `qinling/brieflow_output/`)

3. **Upload config**: `gcs_utils/upload_config.sh screen-name` → creates `gs://your-bucket/screen-name/config/`

4. **Upload input data**: Use `gcs_utils/upload_data.sh` → place at `gs://your-bucket/screen-name/input_ph/`

**Workflow:**
1. Upload input imaging data to `gs://your-bucket/screen-name/input_ph/` (one-time)
2. Run configuration notebook in `analysis/` - set `root_fp: screen-name/brieflow_output/`
3. Upload `analysis/config/` → `gs://your-bucket/screen-name/config/` (via `upload_config.sh`)
4. Run batch script - outputs go to `gs://your-bucket/screen-name/brieflow_output/`

### Cleaning Up Outputs

Use the `gcs_utils/` scripts to clean up outputs and jobs:

```bash
# Replace with your actual bucket and screen name
# Example: gs://scale1/qinling/brieflow_output/

# Delete GCS output only
gcs_utils/delete_output.sh gs://your-bucket/screen-name/brieflow_output/

# Delete GCS output AND associated batch jobs
gcs_utils/delete_output.sh gs://your-bucket/screen-name/brieflow_output/ --delete-jobs

# Delete only failed batch jobs
gcs_utils/delete_batch_jobs.sh --state FAILED

# Delete succeeded jobs older than 7 days
gcs_utils/delete_batch_jobs.sh --state SUCCEEDED --days 7
```

All cleanup scripts include safety prompts and dry-run options. See [`gcs_utils/README.md`](gcs_utils/README.md) for complete documentation.

---

## Running Workflows

### Understanding the Execution Requirements

**Key concept:** When using Google Batch, snakemake packages your current working directory and deploys it to remote workers. The Snakefile must be at the root of this deployed directory, which means you must run snakemake from `brieflow/workflow/`.

**Your workflow setup:** You have numbered run scripts in `analysis/` that correspond to each workflow step. For Google Batch, these scripts need to:
1. Change directory to `brieflow/workflow/` before running snakemake
2. Reference your `analysis/config/` and `analysis/google_batch/` files using relative paths (e.g., `../../analysis/config/config.yml`)

### Batch Run Scripts in analysis/

Batch-enabled run scripts have been created in your `analysis/` directory:

- `1.run_preprocessing_batch.sh` - preprocessing
- `4a.run_sbs_batch.sh` - SBS analysis
- `4b.run_phenotype_batch.sh` - phenotype analysis
- `6.run_merge_batch.sh` - merge
- `8.run_aggregate_batch.sh` - aggregate
- `10.run_cluster_batch.sh` - clustering

Each script follows this pattern:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../brieflow/workflow" || exit 1  # Navigate to workflow dir

snakemake --executor googlebatch \
    --workflow-profile "../../analysis/google_batch/" \
    --configfile "../../analysis/config/config.yml" \
    --until <target>  # all_preprocess, all_sbs, all_phenotype, etc.
    # ... other flags
```

This allows you to run them directly from the `analysis/` directory while ensuring proper deployment to Google Batch workers.

### Command Breakdown

| Flag | Description |
|------|-------------|
| `--executor googlebatch` | Use Google Batch executor |
| `--workflow-profile` | Path to profile directory with config.yaml |
| `--configfile` | Path to workflow config.yml (dataset-specific) |
| `--rerun-triggers mtime` | Re-run jobs if input files modified |
| `--default-storage-provider gcs` | Use GCS for remote storage |
| `--default-storage-prefix` | GCS bucket URL |
| `--until <target>` | Run workflow up to specific target |

### Connecting to Your Controller VM

You need SSH access to your VM for running Jupyter notebooks and executing batch scripts. The easiest way to set up SSH access is to use `gcloud compute config-ssh`, which automatically adds your VM to `~/.ssh/config` with the correct SSH keys. After running this command, your VM will appear in VSCode's Remote-SSH extension for one-click connection.

**VSCode (for interactive work):** After running `gcloud compute config-ssh`, install the Remote-SSH extension, open the Remote Explorer, and connect to your VM. Use this for running configuration notebooks.

**Terminal SSH (for tmux):** Connect via `gcloud compute ssh VM_NAME` or directly via `ssh VM_NAME` (after running `gcloud compute config-ssh`). Use this for long-running batch workflows with tmux.

### Using tmux for Long-Running Workflows

Batch workflows can run for hours or days. Use tmux to ensure they continue even if your SSH connection drops.

**Pattern:**
```bash
ssh user@vm-ip
cd analysis && conda activate brieflow_SCREEN_NAME
tmux new-session -s preprocessing    # Start session
bash 1.run_preprocessing_batch.sh    # Run workflow
# Press Ctrl+b then d to detach (keeps running)
tmux attach -t preprocessing          # Later: reattach to check progress
```

**Common commands:** `tmux ls` (list sessions), `tmux attach -t <name>` (reattach), `tmux kill-session -t <name>` (terminate).

### Typical Analysis Workflow

For each workflow step, follow this simple pattern:

**1. Configure** → Run configuration notebook (generates files in `analysis/config/`)
**2. Prepare** → Run `gcs_utils/upload_config.sh` (uploads to GCS + updates paths)
**3. Execute** → Run batch script (submits jobs to Google Batch)

**Example - Preprocessing:**
```bash
conda activate brieflow_SCREEN_NAME

# Step 1: Configure
cd analysis
jupyter notebook 0.configure_preprocess_params.ipynb

# Step 2: Prepare config for batch
cd ..
gcs_utils/upload_config.sh my_screen
# This:
#  - Uploads TSV files, models, etc. to GCS
#  - Updates config.yml paths to reference GCS
#  - Copies config.yml to brieflow/workflow/

# Step 3: Execute workflow
cd analysis
./1.run_preprocessing_batch.sh
```

**Complete workflow steps:**

| Step | Notebook | Prepare Config | Batch Script | Tmux Session |
|------|----------|----------------|--------------|--------------|
| Preprocess | 0.configure_preprocess_params | `gcs_utils/upload_config.sh` | `1.run_preprocessing_batch.sh` | `preprocessing` |
| SBS | 2.configure_sbs_params | `gcs_utils/upload_config.sh` | `4a.run_sbs_batch.sh` | `sbs` |
| Phenotype | 3.configure_phenotype_params | `gcs_utils/upload_config.sh` | `4b.run_phenotype_batch.sh` | `phenotype` |
| Merge | 5.configure_merge_params | `gcs_utils/upload_config.sh` | `6.run_merge_batch.sh` | `merge` |
| Aggregate | 7.configure_aggregate_params | `gcs_utils/upload_config.sh` | `8.run_aggregate_batch.sh` | `aggregate` |
| Cluster | 9.configure_cluster_params | `gcs_utils/upload_config.sh` | `10.run_cluster_batch.sh` | `cluster` |

**Important:** Run `upload_config.sh` after EACH notebook, as notebooks update the config files.

---

## Performance Optimization

This section covers critical optimizations that can improve workflow performance from **8-16 hours to 12-20 minutes** for 10,000-job workflows.

### Overview: Performance Bottlenecks and Solutions

| Bottleneck | Impact | Solution | Speedup |
|------------|--------|----------|---------|
| **DAG building with GCS checks** | 5+ hours | Add `input-output` to `shared-fs-usage` | 20-60x |
| **Job submission rate limit** | 8-13 hours | Use `--max-jobs-per-timespan "10000/1s"` | 10-100x |
| **VM type and quota** | 3-min provisioning, 125 VMs | Switch to n2 spot (2,500 VMs) | 20x capacity |
| **Log retrieval delays** | Variable | Optional patch (test first) | Variable |

**Combined result:** ~30 minutes total (10 min DAG + 20 min execution) vs 13+ hours!

### 1. Critical: Fix DAG Building (5+ Hour Savings!)

**Problem:** Without `input-output` in `shared-fs-usage`, Snakemake checks if EVERY input/output file exists on GCS during DAG building.
- 10,776 jobs × 2 API calls per job = 21,552+ GCS API calls
- Each call has network latency (~1-2 seconds)
- Total: 5+ hours just to build the DAG before any jobs start

**Solution:** Already configured in `analysis/google_batch/config.yaml`:
```yaml
shared-fs-usage:
  - persistence
  - source-cache
  - sources
  - input-output          # ← THE KEY FIX!
  - storage-local-copies
```

**What this does:** Tells Snakemake "trust that GCS files are accessible, don't verify each one exists during DAG building"

**Impact:** DAG building time: 5 hours → 5-15 minutes (20-60x faster!)

### 2. Fix Job Submission Rate

**Problem:** Snakemake's default `--max-jobs-per-timespan "100/1s"` submits only 100 jobs at a time, then waits for ALL to complete before submitting the next batch.

**Solution:** Already configured in batch run scripts:
```bash
--max-jobs-per-timespan "10000/1s" \
--max-status-checks-per-second 1 \
--seconds-between-status-checks 30
```

**Impact:** Submit all jobs immediately instead of in 100-job waves.

### 3. Optimize VM Type and Use Spot Instances

**VM type comparison (us-west1 quota):**

| Machine Type | CPUs per VM | Quota | Max Concurrent VMs | Provisioning Time | Cost Savings |
|--------------|-------------|-------|-------------------|-------------------|--------------|
| c2-standard-4 | 4 | 500 | 125 VMs | ~180s (3 min) | 0% (baseline) |
| n2-standard-4 | 4 | 3,000 | 750 VMs | ~45-90s | Similar |
| **n2 spot** | **4** | **10,000** | **2,500 VMs** | **~45-90s** | **60-90% cheaper** |

**Solution:** Already configured:
- `config.yaml`: `googlebatch_machine_type: "n2-standard-4"`
- Batch scripts: `--preemptible-rules` and `--preemptible-retries 3`

**Impact:** 2,500 concurrent VMs instead of 125 (20x more capacity!)

**Trade-offs:**
- Spot instances can be interrupted by Google Cloud
- Jobs automatically retry up to 3 times
- Interruptions are rare for short jobs (~2 minutes)
- 60-90% cost savings typically outweighs interruption risk

### 4. Optional: Disable Log Retrieval

**When needed:** Only enable this optimization if you experience slowdowns after jobs start completing rapidly (2,500+ concurrent VMs).

**Problem:** Snakemake retrieves logs for every completed job, which can block the status checking loop when hundreds of jobs complete per minute.

**Solution:** Use the `patch_googlebatch_logs.py` script (currently commented out in run scripts):

Uncomment these lines in `analysis/1.run_preprocessing_batch.sh`:
```bash
# OPTIONAL: Apply monkey patch to disable log retrieval (prevents API throttling)
# Uncomment the next 3 lines if you experience log retrieval slowdowns
export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
python -c "import patch_googlebatch_logs" && \
```

**How it works:**
- Patches the Google Batch executor to skip automatic log retrieval
- Writes placeholder files with instructions for manual retrieval
- Logs can still be retrieved after workflow completion using `gcloud` or the `get_batch_logs.sh` script

**When to enable:**
- If you see "Too many requests to Google Logging API" errors
- If job completion rate slows down unexpectedly
- When running 2,500+ concurrent VMs with rapid job turnover

**Retrieval after completion:**
```bash
# Using the gcs_utils script (recommended):
gcs_utils/get_batch_logs.sh --state FAILED

# Or manually with gcloud:
gcloud logging read "labels.job_uid=<JOB_UID>" \
  --project=your-project-id \
  --format=json
```

### Expected Performance: Before vs After

**Scenario:** 10,000 preprocessing jobs (typical brieflow workflow)

| Phase | Before Optimization | After Optimization | Speedup |
|-------|-------------------|-------------------|---------|
| **DAG Building** | 5 hours (GCS API calls) | 10 minutes | 30x |
| **Job Submission** | 100 jobs at a time | All 10K jobs at once | 100x |
| **Execution (c2)** | 8.3 hours (125 VMs, 100-job waves) | 6.7 hours (125 VMs, all at once) | 1.2x |
| **Execution (n2 spot)** | N/A | 12-20 minutes (2,500 VMs) | 25-40x |
| **Total Time** | **13+ hours** | **~30 minutes** | **~25x** |

**Breakdown for n2 spot (2,500 concurrent VMs):**
- Concurrent capacity: 2,500 VMs
- Number of waves: 10,000 ÷ 2,500 = 4 waves
- Time per wave: 1 min provision + 2 min run = 3 minutes
- Total execution: 4 waves × 3 min = 12 minutes
- Plus DAG building: 10 minutes
- **Grand total: ~22 minutes**

### Verification Checklist

After applying optimizations, verify they're working:

- [ ] **DAG building completes in <15 minutes** (not 5+ hours)
  - Check Snakemake output: "Building DAG of jobs..." should complete quickly

- [ ] **All jobs submit immediately** (not in batches of 100)
  - Look for "Execute N jobs..." message showing all jobs at once

- [ ] **Jobs use n2-standard-4 VMs**
  - Check: `gcloud batch jobs describe JOB_ID --format=json | jq '.allocationPolicy.instances[0].policy.machineType'`

- [ ] **Spot instances are enabled** (if using `--preemptible-rules`)
  - Check: `gcloud batch jobs describe JOB_ID --format=json | jq '.allocationPolicy.instances[0].policy.provisioningModel'`
  - Should show: `"SPOT"` or `"PREEMPTIBLE"`

- [ ] **High concurrency achieved** (hundreds to thousands of running jobs)
  - Monitor: `gcloud batch jobs list --filter="state=RUNNING" | wc -l`

### Troubleshooting Performance Issues

**If DAG building still takes hours:**
- Verify `input-output` is in `shared-fs-usage` in `config.yaml`
- Check that `--default-storage-provider gcs` is specified in batch script

**If jobs submit in batches of 100:**
- Verify `--max-jobs-per-timespan "10000/1s"` is in batch script
- Check Snakemake output for "Execute 100 jobs..." (should show all jobs)

**If provisioning is slow:**
- Verify `googlebatch_machine_type: "n2-standard-4"` in `config.yaml`
- Check quota: `gcloud compute regions describe us-west1 --format="table(quotas.metric,quotas.limit,quotas.usage)"`

**If many spot instances are interrupted:**
- Monitor interruption rate: `gcloud batch jobs list --filter="state=FAILED" | grep -i preempt | wc -l`
- Consider reducing concurrency or using standard (non-spot) instances
- Increase retry count in config.yaml: `googlebatch_retry_count: 3`

---

## Monitoring and Debugging

### GCS Utilities Overview

The `gcs_utils/` directory contains scripts for data management, monitoring, and cleanup:

| Script | Purpose |
|--------|---------|
| `upload_data.sh` | Upload files/directories to GCS with confirmation |
| `list_data.sh` | List GCS bucket contents with filtering options |
| `get_batch_logs.sh` | Retrieve and search batch job logs |
| `delete_output.sh` | Delete GCS outputs and optionally associated jobs |
| `delete_batch_jobs.sh` | Delete batch jobs by state, age, or pattern |

**Quick reference:**
```bash
# Upload data (replace with your storage prefix)
gcs_utils/upload_data.sh <local_path> gs://your-bucket/your-screen/input_ph/

# List bucket contents
gcs_utils/list_data.sh gs://your-bucket/your-screen/

# Get batch job logs
gcs_utils/get_batch_logs.sh <job_name>

# Get logs for all failed jobs
gcs_utils/get_batch_logs.sh --state FAILED

# Delete failed jobs
gcs_utils/delete_batch_jobs.sh --state FAILED
```

**See [`gcs_utils/README.md`](gcs_utils/README.md) for complete documentation with examples and advanced options.**

### Listing Batch Jobs

```bash
# List all jobs in region
gcloud batch jobs list --location=us-west1

# Filter by state
gcloud batch jobs list --location=us-west1 --filter="state=RUNNING"

# Get job details
gcloud batch jobs describe JOB_ID --location=us-west1
```

### Retrieving Job Logs

The `get_batch_logs.sh` script retrieves and organizes batch job logs:

```bash
# Get logs for a specific job
gcs_utils/get_batch_logs.sh <job-id>

# Get logs for all failed jobs
gcs_utils/get_batch_logs.sh --state FAILED

# Search for specific errors in logs
gcs_utils/get_batch_logs.sh --pattern "AttributeError" --state FAILED
```

**Log output structure** (`batch_logs/<job-id>/`):
- `batch_task_logs.txt` - Container stdout/stderr (your workflow output)
- `batch_agent_logs.txt` - Batch agent logs (system logs)
- `cloud_logs.txt` - Cloud logging messages
- `job_details.json` - Full job configuration
- `SUMMARY.txt` - Key errors and job info extracted

See [`gcs_utils/README.md`](gcs_utils/README.md) for advanced search and filtering options.

### Common Log Patterns

**Success indicators:**
```
Building DAG of jobs...
Select jobs to execute...
[date] rule <rule_name>:
[date] Finished job <job_id>.
```

**Failure indicators:**
```
ERROR: Dependency conflict
AttributeError: 'NoneType' object has no attribute 'size'
/bin/bash: ... File name too long
Failed to get expected local footprint
```

### Checking Outputs in GCS

Use the `list_data.sh` script to inspect workflow outputs:

```bash
# Replace with your bucket and screen name
# Example: gs://scale1/qinling/brieflow_output/

# List output files with sizes
gcs_utils/list_data.sh gs://your-bucket/screen-name/brieflow_output/

# List specific step outputs recursively
gcs_utils/list_data.sh gs://your-bucket/screen-name/brieflow_output/preprocess/ -r

# Check file sizes and counts
gcs_utils/list_data.sh gs://your-bucket/screen-name/brieflow_output/ -r -s
```

Or use `gsutil` directly:
```bash
gsutil ls -lh gs://your-bucket/screen-name/brieflow_output/
```

---

## Cost Optimization

### Using Preemptible VMs

Add to config.yaml:
```yaml
default-resources:
  googlebatch_provisioning_model: "PREEMPTIBLE"
```

Savings: Up to 80% vs standard VMs
Trade-off: Jobs may be interrupted (use `googlebatch_retry_count`)

### Rightsizing Resources

Monitor job resource usage:
```bash
# Get job metrics
gcloud batch jobs describe JOB_ID --location=us-west1 --format=json | \
    jq '.status.taskGroups[0].instances[0].machineStatus'
```

Adjust resources based on actual usage to avoid over-provisioning.

### Lifecycle Policies

Set GCS lifecycle policies to auto-delete old outputs:
```bash
gsutil lifecycle set lifecycle.json gs://your-bucket
```

**lifecycle.json:**
```json
{
  "rule": [{
    "action": {"type": "Delete"},
    "condition": {
      "age": 90,
      "matchesPrefix": ["brieflow_output/"]
    }
  }]
}
```

---

## Account Permissions Summary

### User Account (Controller Machine)

Your GCP user account (runs `snakemake` command) needs:

**Project-level IAM roles:**
- `roles/editor` or `roles/owner` - Create batch jobs, manage resources
- `roles/storage.admin` - Read/write GCS buckets
- `roles/cloudbuild.builds.editor` - Build Docker images
- `roles/batch.jobsEditor` - Create and manage batch jobs

**Check your permissions:**
```bash
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:YOUR_EMAIL"
```

### Service Account (Batch Workers)

Service account `batch-sa@PROJECT_ID.iam.gserviceaccount.com` needs:

**Project-level IAM roles:**
- `roles/batch.agentReporter` - Report batch job status
- `roles/compute.instanceAdmin.v1` - Manage VM instances
- `roles/iam.serviceAccountUser` - Use service account
- `roles/logging.logWriter` - Write logs
- `roles/serviceusage.serviceUsageConsumer` - Use GCP services

**Bucket-level IAM roles** (on your GCS bucket):
- `roles/storage.admin` - Full bucket access
- `roles/storage.objectAdmin` - Create/delete objects

**Why separate permissions?**
- Service account has **minimal** project-level permissions (security best practice)
- Service account has **full** access to specific GCS bucket (for data I/O)
- User account has **broad** permissions (for setup and management)

**Grant service account bucket access:**
```bash
gsutil iam ch serviceAccount:batch-sa@PROJECT_ID.iam.gserviceaccount.com:roles/storage.admin gs://your-bucket
gsutil iam ch serviceAccount:batch-sa@PROJECT_ID.iam.gserviceaccount.com:roles/storage.objectAdmin gs://your-bucket
```

---

## Summary Checklist

**Infrastructure Setup (One-time):**
- [ ] GCP project created with required APIs enabled (batch, storage, artifactregistry, cloudbuild)
- [ ] Service account created (`batch-sa`) with correct project-level roles
- [ ] User account has editor/owner + storage.admin + cloudbuild.builds.editor roles
- [ ] GCS bucket created for data and outputs
- [ ] Service account granted storage.admin + storage.objectAdmin on bucket
- [ ] Artifact Registry repository created for Docker images
- [ ] Docker image built using `build_docker.sh` (with feat/allow-custom-containers executor plugin)
- [ ] Input imaging data uploaded to GCS bucket

**Workflow Configuration (Per Analysis):**
- [ ] Created `analysis/google_batch/config.yaml` with your project/bucket settings
- [ ] Verified `googlebatch-container-dependencies-installed: true` in config.yaml
- [ ] Google Batch run scripts ready in `analysis/` (1, 4a, 4b, 6, 8, 10)
- [ ] Understand the workflow: **Notebook → Upload config → Run batch script**
- [ ] Run configuration notebooks to generate config files
- [ ] **CRITICAL:** Upload `analysis/config/` after EACH notebook using `gcs_utils/upload_config.sh`
- [ ] Test workflow with dry-run first
- [ ] Reviewed [`gcs_utils/README.md`](gcs_utils/README.md) for utilities

---

**Last Updated:** October 21, 2025
**Executor Plugin:** mboulton-fathom/feat/allow-custom-containers (unmerged PR)
**Snakemake Version:** 9.12.0
