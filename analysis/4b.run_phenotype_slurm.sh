#!/bin/bash

# Log all output to a log file (stdout and stderr)
mkdir -p slurm/slurm_output/main
start_time_formatted=$(date +%Y%m%d_%H%M%S)
log_file="slurm/slurm_output/main/phenotype-${start_time_formatted}.log"
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
        --groups apply_ic_field_phenotype=extract_phenotype_info_group \
                align_phenotype=extract_phenotype_info_group \
                segment_phenotype=extract_phenotype_info_group \
                extract_phenotype_info=extract_phenotype_info_group \
                identify_cytoplasm=extract_phenotype_cp_group \
                extract_phenotype_cp=extract_phenotype_cp_group \
        --until all_phenotype \
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
