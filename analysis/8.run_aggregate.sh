#!/bin/bash

# Run the aggregate rules
snakemake --use-conda --cores all \
    --snakefile "../brieflow/workflow/Snakefile" \
    --configfile "config/config.yml" \
    --rerun-triggers mtime \
    --keep-going \
    --until all_aggregate -n -n
