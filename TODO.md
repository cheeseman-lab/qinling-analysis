# TODO - Google Batch Workflow

## High Priority

### [x] ~~Test if config.yml can be read from GCS directly~~ **COMPLETED - DOES NOT WORK**
**Question:** Can we use `--configfile "gs://brieflow-qinling-staging/my_screen/config/config.yml"` instead of deploying it with the workflow?

**Result: NO** ❌

**Why it doesn't work:**
- Snakemake mangles GCS paths: `gs://bucket/...` becomes `gs:/bucket/...` (single slash)
- This is a known issue with remote executors (Slurm, Google Batch, etc.)
- See GitHub issue: snakemake#2846 - "Remote executors cannot detect the config.yaml file under initial workspace"
- The `configfile:` statement in Snakefile looks for files in `workdir`, not where you run from

**Solution implemented:**
`upload_config.sh` now does 3 things:
1. Uploads config files (TSV, models, etc.) to GCS
2. Updates config.yml paths to reference GCS locations
3. Copies the GCS-updated config.yml to `brieflow/workflow/config.yml`

This way:
- Config files (TSV, models) are in GCS ✓
- config.yml is in workflow/ (gets deployed to workers) ✓
- All paths in config.yml reference GCS ✓

---

### [ ] Monitor if grouped/group jobs work in Google Batch

**Context:**
- Snakemake can group multiple rules into a single batch job
- This reduces overhead and can be more cost-effective
- Need to verify this works with Google Batch executor

**To test:**
1. Add group definitions to workflow
2. Run a test workflow with grouped jobs
3. Monitor if:
   - Jobs are properly grouped
   - All tasks in a group execute correctly
   - Resource allocation works as expected
   - Logs are properly captured

**Documentation needed:**
- If groups work, document best practices for grouping rules
- Add examples to GOOGLE_BATCH_SETUP.md

---

## Medium Priority

### [ ] Verify config upload workflow is clear
- [ ] Test the full workflow from notebook → upload → batch
- [ ] Ensure `gcs_utils/upload_config.sh` uploads all necessary files
- [ ] Verify that batch workers can access all uploaded files

### [ ] Test dry-run workflow
- [ ] Verify `--dry-run` works correctly from workflow directory
- [ ] Check that it shows expected DAG

### [ ] Create helper script to copy config to workflow
If GCS config doesn't work, create a simple script:
- `copy_config_to_workflow.sh` - copies `analysis/config/config.yml` to `brieflow/workflow/config.yml`
- Integrate into workflow documentation

---

## Low Priority

### [ ] Optimize resource allocations
- [ ] Monitor actual memory usage of jobs
- [ ] Adjust `set-resources` in `google_batch/config.yaml` based on observations
- [ ] Document any patterns (e.g., which rules consistently use less than allocated)

### [ ] Test preemptible VMs
- [ ] Enable preemptible VMs in config
- [ ] Monitor failure rates
- [ ] Document cost savings vs reliability trade-offs

### [ ] Create troubleshooting runbook
- [ ] Common error patterns and solutions
- [ ] Quick debugging checklist
- [ ] Links to relevant log commands

---

## Questions to Answer

1. **Does Snakemake support reading `--configfile` from GCS paths?**
2. **Can we avoid copying config.yml to workflow/ entirely?**
3. **Do grouped jobs reduce costs and improve performance?**
4. **What's the optimal retry strategy for failed jobs?**
5. **Should we use SPOT/preemptible VMs by default?**

---

## Completed
- [x] Create `gcs_utils/` scripts for data management
- [x] Create `analysis/google_batch/config.yaml` profile
- [x] Create batch run scripts (1, 4a, 4b, 6, 8, 10)
- [x] Update GOOGLE_BATCH_SETUP.md for analysis/ workflow
- [x] Create succinct gcs_utils/README.md
- [x] Test GCS config path approach (doesn't work - Snakemake issue)
- [x] Implement 3-step upload_config.sh (upload + transform + copy)
- [x] Update all batch scripts to use `--configfile "config.yml"`
- [x] Document final workflow in GOOGLE_BATCH_SETUP.md
