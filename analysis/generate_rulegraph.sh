#!/bin/bash

# Generate a rulegraph of the Snakefile
snakemake \
    --snakefile "../brieflow/workflow/Snakefile" \
    --configfile "config/config.yml" \
    --until all_aggregate \
    --rulegraph | dot -Gdpi=100 -Tpng -o "../images/brieflow_rulegraph.png"
