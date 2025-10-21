#!/usr/bin/env python3
"""
Monkey patch for snakemake-executor-plugin-googlebatch to disable log retrieval.

This fixes the performance issue where retrieving logs for finished jobs
can cause delays due to Google Cloud Logging API rate limits (60 requests/minute).

GitHub Issue: https://github.com/snakemake/snakemake-executor-plugin-googlebatch/issues/14

Usage:
    1. Save this file as patch_googlebatch_logs.py
    2. Import it before running snakemake:

       python -c "import patch_googlebatch_logs" && snakemake --executor googlebatch ...

       Or in a Python script:
       import patch_googlebatch_logs
       # then run snakemake normally

Note:
    Logs can still be retrieved manually after workflow completion using:
    gcloud logging read "labels.job_uid=<JOB_UID>" --project=<PROJECT_ID>
"""

import sys


def apply_patch():
    """Apply the monkey patch to disable log retrieval during execution"""
    try:
        import snakemake_executor_plugin_googlebatch.executor as executor_module
    except ImportError:
        print("ERROR: snakemake-executor-plugin-googlebatch not installed", file=sys.stderr)
        sys.exit(1)

    # Save original method for reference
    _original_save_logs = executor_module.GoogleBatchExecutor.save_finished_job_logs

    def skip_log_retrieval(self, job_info, sleeps=60, page_size=1000):
        """
        Skip log retrieval during execution to avoid rate limits.

        The Google Cloud Logging API has a limit of 60 requests per minute,
        which can cause delays when retrieving logs for large numbers of jobs.

        Instead, we write a placeholder file with instructions for manual retrieval.
        """
        logfname = job_info.aux["logfile"]
        job_uid = job_info.aux["batch_job"].uid
        job_name = job_info.aux["batch_job"].name

        # Write placeholder with retrieval instructions
        try:
            with open(logfname, "w", encoding="utf-8") as logfile:
                logfile.write("=" * 80 + "\n")
                logfile.write("LOG RETRIEVAL DISABLED (Performance Optimization)\n")
                logfile.write("=" * 80 + "\n\n")
                logfile.write(f"Job Name: {job_name}\n")
                logfile.write(f"Job UID:  {job_uid}\n\n")
                logfile.write("Automatic log retrieval was disabled to avoid Google Cloud\n")
                logfile.write("Logging API rate limits (60 requests/minute) that can cause\n")
                logfile.write("performance issues for large workflows.\n\n")
                logfile.write("To retrieve logs manually:\n\n")
                logfile.write("  # Using gcloud CLI:\n")
                logfile.write(f'  gcloud logging read "labels.job_uid={job_uid}" \\\n')
                logfile.write(f"    --project={self.executor_settings.project} \\\n")
                logfile.write(f"    --format=json > {logfname}.json\n\n")
                logfile.write("  # Or view in Cloud Console:\n")
                logfile.write(f"  https://console.cloud.google.com/logs/query;query=labels.job_uid%3D{job_uid}\n\n")
        except Exception as e:
            self.logger.warning(f"Failed to write placeholder log file: {e}")

        # Log that we skipped retrieval (debug level to avoid spam)
        self.logger.debug(
            f"Skipped log retrieval for job {job_uid} (performance optimization)"
        )

    # Apply the monkey patch
    executor_module.GoogleBatchExecutor.save_finished_job_logs = skip_log_retrieval

    print("✓ Applied patch: Log retrieval disabled for Google Batch executor")
    print("  Jobs will complete faster without log retrieval delays")
    print("  Retrieve logs manually after workflow completion if needed")


# Apply patch on import
apply_patch()
