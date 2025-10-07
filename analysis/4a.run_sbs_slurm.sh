#!/bin/bash

# Log all output to a log file (stdout and stderr)
mkdir -p slurm/slurm_output/main
start_time_formatted=$(date +%Y%m%d_%H%M%S)
log_file="slurm/slurm_output/main/sbs-${start_time_formatted}.log"
exec > >(tee -a "$log_file") 2>&1

# Start timing
start_time=$(date +%s)

# TODO: Set number of plates to process
NUM_PLATES=None

echo "===== STARTING SEQUENTIAL PROCESSING OF $NUM_PLATES PLATES ====="

# Process each plate in sequence
for PLATE in $(seq 1 $NUM_PLATES); do
    echo ""
    echo "==================== PROCESSING PLATE $PLATE ===================="
    echo "Started at: $(date)"
    
    # Start timing for this plate
    plate_start_time=$(date +%s)
    
    # Run Snakemake with plate filter for this plate
    snakemake --executor slurm --use-conda \
        --workflow-profile "slurm/" \
        --snakefile "../brieflow/workflow/Snakefile" \
        --configfile "config/config.yml" \
        --latency-wait 60 \
        --rerun-triggers mtime \
        --keep-going \
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
