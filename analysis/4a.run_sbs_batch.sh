#!/bin/bash
# Run SBS analysis with Google Batch executor
#
# Prerequisites:
# 1. Run 2.configure_sbs_params.ipynb
# 2. Upload config: gcs_utils/upload_config.sh my_screen

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log all output to a log file (stdout and stderr)
mkdir -p "$SCRIPT_DIR/batch"
start_time_formatted=$(date +%Y%m%d_%H%M%S)
log_file="$SCRIPT_DIR/batch/sbs-${start_time_formatted}.log"
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
    cd "$SCRIPT_DIR/../brieflow/workflow" || exit 1

    # Run Snakemake with plate filter for this plate
    snakemake --executor googlebatch \
        --workflow-profile "../../analysis/google_batch/" \
        --snakefile "Snakefile" \
        --configfile "config.yml" \
        --rerun-triggers mtime \
        --default-storage-provider gcs \
        --default-storage-prefix "gs://scale1" \
        --storage-gcs-project lasagna-199723 \
        --rerun-incomplete \
        --groups align_sbs=extract_sbs_info_group \
                apply_ic_field_sbs=extract_sbs_info_group \
                segment_sbs=extract_sbs_info_group \
                extract_sbs_info=extract_sbs_info_group \
                log_filter=max_filter_group \
                max_filter=max_filter_group \
                compute_standard_deviation=find_peaks_group \
                find_peaks=find_peaks_group \
                extract_bases=call_cells_group \
                call_reads=call_cells_group \
                call_cells=call_cells_group \
        --until all_sbs \
        --config plate_filter=$PLATE

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
