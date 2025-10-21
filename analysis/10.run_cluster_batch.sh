#!/bin/bash
# Run cluster step with Google Batch executor
#
# Prerequisites:
# 1. Run 9.configure_cluster_params.ipynb to update config files
# 2. Upload config/ to GCS: ../gcs_utils/upload_data.sh config/ gs://bucket/screen/config/
# 3. Complete aggregate step first (8.run_aggregate_batch.sh)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log all output to a log file (stdout and stderr)
mkdir -p "$SCRIPT_DIR/batch"
start_time_formatted=$(date +%Y%m%d_%H%M%S)
log_file="$SCRIPT_DIR/batch/cluster-${start_time_formatted}.log"
exec > >(tee -a "$log_file") 2>&1

# Start timing
start_time=$(date +%s)

# CRITICAL: Change to workflow directory so Snakefile is at root of deployed directory
cd "$SCRIPT_DIR/../brieflow/workflow" || exit 1

# Run with Google Batch executor
snakemake --executor googlebatch \
    --workflow-profile "../../analysis/google_batch/" \
    --snakefile "Snakefile" \
    --configfile "config.yml" \
    --rerun-triggers mtime \
    --default-storage-provider gcs \
    --default-storage-prefix "gs://scale1" \
    --storage-gcs-project lasagna-199723 \
    --rerun-incomplete \
    --until all_cluster

# End timing and calculate duration
end_time=$(date +%s)
duration=$((end_time - start_time))
echo "Total runtime: $((duration / 3600))h $(((duration % 3600) / 60))m $((duration % 60))s"
