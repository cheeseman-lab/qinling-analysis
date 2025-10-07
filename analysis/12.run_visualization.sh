#!/bin/bash

export BRIEFLOW_OUTPUT_PATH="brieflow_output/"
export CONFIG_PATH="config/config.yml"
export SCREEN_PATH="screen.yaml"

# Start Streamlit server, force bind to 0.0.0.0
exec streamlit run ../brieflow/visualization/Experimental_Overview.py --server.address=0.0.0.0 "$@"