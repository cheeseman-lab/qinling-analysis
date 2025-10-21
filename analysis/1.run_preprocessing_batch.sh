#!/bin/bash
# Run preprocessing step with Google Batch executor
#
# Prerequisites:
# 1. Run 0.configure_preprocess_params.ipynb to generate config files
# 2. Upload config: gcs_utils/upload_config.sh my_screen
#    (This uploads files to GCS and copies config.yml to workflow/)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log all output to a log file (stdout and stderr)
mkdir -p "$SCRIPT_DIR/batch"
start_time_formatted=$(date +%Y%m%d_%H%M%S)
log_file="$SCRIPT_DIR/batch/preprocessing-${start_time_formatted}.log"
exec > >(tee -a "$log_file") 2>&1

# Start timing
start_time=$(date +%s)

# Set number of plates to process
NUM_PLATES=1

echo "===== STARTING SEQUENTIAL PROCESSING OF $NUM_PLATES PLATES ====="

# Process each plate in sequence
for PLATE in $(seq 1 $NUM_PLATES); do
    echo ""
    echo "==================== PROCESSING PLATE $PLATE ===================="
    echo "Started at: $(date)"

    # Start timing for this plate
    plate_start_time=$(date +%s)

    # CRITICAL: Change to workflow directory so Snakefile is at root of deployed directory
    # This is required for Google Batch to properly deploy the workflow code
    cd "$SCRIPT_DIR/../brieflow/workflow" || exit 1

    # Apply monkey patch to disable log retrieval (prevents API throttling)
    export PYTHONPATH="$SCRIPT_DIR/..:$PYTHONPATH"
    python -c "import patch_googlebatch_logs" && \

    # Run Snakemake with ALL optimizations
    # Most settings come from workflow-profile, but DAG optimization flags must be on command line
    snakemake \
        --workflow-profile "../../analysis/google_batch/" \
        --snakefile "Snakefile" \
        --configfile "config.yml" \
        --until all_preprocess \
        --config plate_filter=$PLATE \
        \
        `# DAG BUILDING OPTIMIZATIONS (CRITICAL - these cannot be set in config.yaml)` \
        --latency-wait 0 \
        --max-inventory-time 300 \
        --ignore-incomplete \
        --max-checksum-file-size 0

    # Check if Snakemake was successful
    if [ $? -ne 0 ]; then
        echo "ERROR: Processing of plate $PLATE failed. Stopping sequential run."
        exit 1
    fi

    # End timing and calculate duration for this plate
    plate_end_time=$(date +%s)
    plate_duration=$((plate_end_time - plate_start_time))

    echo "==================== PLATE $PLATE COMPLETED ===================="
    echo "Finished at: $(date)"
    echo "Runtime for plate $PLATE: $((plate_duration / 3600))h $(((plate_duration % 3600) / 60))m $((plate_duration % 60))s"
    echo ""

    # Optional: Add a short pause between plates
    sleep 10
done

echo "===== ALL $NUM_PLATES PLATES PROCESSED SUCCESSFULLY ====="

# End timing and calculate total duration
end_time=$(date +%s)
duration=$((end_time - start_time))
echo "Total runtime: $((duration / 3600))h $(((duration % 3600) / 60))m $((duration % 60))s"